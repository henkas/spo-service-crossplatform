using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.SharePoint.Client;

namespace SPOService.CrossPlatform;

// Root cause being worked around:
// Microsoft.SharePoint.Client.HttpWebRequestExecutor (from the SPO module's 16.0.0.0
// Microsoft.SharePoint.Client.Runtime.dll) was compiled against .NET Framework's
// HttpWebRequest. On PowerShell 7 / .NET Core on macOS, its GetRequestStream path
// does not actually flush the body bytes to the socket, so SharePoint receives
// Content-Length: 0 POSTs and responds with "Invalid request." / 400 Bad Request.
//
// This executor replaces that pipeline by buffering the body, then sending it via
// HttpClient with the correct headers and content type.
public sealed class HttpClientExecutor : WebRequestExecutor
{
    private static readonly HttpClient s_http = BuildHttpClient();

    private readonly string _url;
    private readonly WebHeaderCollection _requestHeaders = new WebHeaderCollection();
    private WebHeaderCollection _responseHeaders = new WebHeaderCollection();
    private MemoryStream _requestBody;
    private MemoryStream _responseBody;
    private HttpResponseMessage _response;
    private string _contentType;
    private string _method = "GET";
    private bool _keepAlive = true;
    private HttpStatusCode _statusCode;
    private string _responseContentType;
    private HttpWebRequest _legacyWebRequest;

    public HttpClientExecutor(string url)
    {
        _url = url;
    }

    private static HttpClient BuildHttpClient()
    {
        var handler = new SocketsHttpHandler
        {
            AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate,
            AllowAutoRedirect = true,
            // CSOM is bearer-token auth; no Set-Cookie round-trip matters for the
            // operations this module exposes. Cookies stay off so the static
            // HttpClient cannot accumulate cross-session state across reconnects.
            UseCookies = false,
            PooledConnectionLifetime = TimeSpan.FromMinutes(10),
        };
        var c = new HttpClient(handler, disposeHandler: false);
        c.Timeout = TimeSpan.FromMinutes(30);
        return c;
    }

    public override Stream GetRequestStream()
    {
        _requestBody ??= new MemoryStream();
        return new NonClosingStream(_requestBody);
    }

    // The runtime calls Close/Dispose on the stream returned by GetRequestStream
    // before Execute() runs. That kills the backing MemoryStream, so we wrap it
    // in a pass-through that ignores Close/Dispose on the outer handle.
    private sealed class NonClosingStream : Stream
    {
        private readonly Stream _inner;
        public NonClosingStream(Stream inner) { _inner = inner; }
        public override bool CanRead => _inner.CanRead;
        public override bool CanSeek => _inner.CanSeek;
        public override bool CanWrite => _inner.CanWrite;
        public override long Length => _inner.Length;
        public override long Position { get => _inner.Position; set => _inner.Position = value; }
        public override void Flush() => _inner.Flush();
        public override int Read(byte[] buffer, int offset, int count) => _inner.Read(buffer, offset, count);
        public override long Seek(long offset, SeekOrigin origin) => _inner.Seek(offset, origin);
        public override void SetLength(long value) => _inner.SetLength(value);
        public override void Write(byte[] buffer, int offset, int count) => _inner.Write(buffer, offset, count);
        protected override void Dispose(bool disposing) { /* keep inner open */ }
        public override void Close() { /* keep inner open */ }
    }

    public override Stream GetResponseStream()
    {
        if (_responseBody == null)
        {
            throw new InvalidOperationException("Response has not been read yet.");
        }
        _responseBody.Position = 0;
        return _responseBody;
    }

    public override void Execute()
    {
        RunAsync(default).GetAwaiter().GetResult();
    }

    public override Task ExecuteAsync()
    {
        return RunAsync(default);
    }

    private async Task RunAsync(CancellationToken ct)
    {
        // The original HttpWebRequest-based executor auto-upgrades to POST the moment
        // a body is written via GetRequestStream(). The SPC runtime relies on that
        // implicit behavior for several paths (sites.asmx digest pre-fetch, etc.) and
        // never calls the RequestMethod setter. Preserve that implicit upgrade here.
        var effectiveMethod = _method;
        if (string.Equals(effectiveMethod, "GET", StringComparison.OrdinalIgnoreCase)
            && _requestBody != null && _requestBody.Length > 0)
        {
            effectiveMethod = "POST";
        }

        using var req = new HttpRequestMessage(new HttpMethod(effectiveMethod), _url);

        bool methodHasBody = effectiveMethod != "GET" && effectiveMethod != "HEAD" && effectiveMethod != "DELETE";

        if (_requestBody != null && _requestBody.Length > 0)
        {
            var body = _requestBody.ToArray();
            req.Content = new ByteArrayContent(body);
            if (!string.IsNullOrEmpty(_contentType))
            {
                try { req.Content.Headers.ContentType = MediaTypeHeaderValue.Parse(_contentType); } catch { }
            }
            req.Content.Headers.ContentLength = body.Length;
        }
        else if (methodHasBody)
        {
            req.Content = new ByteArrayContent(Array.Empty<byte>());
            if (!string.IsNullOrEmpty(_contentType))
            {
                try { req.Content.Headers.ContentType = MediaTypeHeaderValue.Parse(_contentType); } catch { }
            }
            req.Content.Headers.ContentLength = 0;
        }

        foreach (string name in _requestHeaders.AllKeys)
        {
            var value = _requestHeaders[name];
            if (string.IsNullOrEmpty(value)) continue;
            if (string.Equals(name, "Content-Type", StringComparison.OrdinalIgnoreCase))
            {
                if (req.Content != null)
                {
                    try { req.Content.Headers.ContentType = MediaTypeHeaderValue.Parse(value); } catch { }
                }
                continue;
            }
            if (string.Equals(name, "Content-Length", StringComparison.OrdinalIgnoreCase)) continue;
            if (string.Equals(name, "Host", StringComparison.OrdinalIgnoreCase)) continue;

            if (!req.Headers.TryAddWithoutValidation(name, value))
            {
                req.Content?.Headers.TryAddWithoutValidation(name, value);
            }
        }

        if (!_keepAlive)
        {
            req.Headers.ConnectionClose = true;
        }

        _response = await s_http.SendAsync(req, HttpCompletionOption.ResponseContentRead, ct).ConfigureAwait(false);
        _statusCode = _response.StatusCode;
        _responseContentType = _response.Content?.Headers?.ContentType?.ToString() ?? string.Empty;

        _responseHeaders = new WebHeaderCollection();
        foreach (var h in _response.Headers)
        {
            _responseHeaders[h.Key] = string.Join(",", h.Value);
        }
        if (_response.Content != null)
        {
            foreach (var h in _response.Content.Headers)
            {
                _responseHeaders[h.Key] = string.Join(",", h.Value);
            }
        }

        _responseBody = new MemoryStream();
        if (_response.Content != null)
        {
            await _response.Content.CopyToAsync(_responseBody, ct).ConfigureAwait(false);
        }
        _responseBody.Position = 0;

        if ((int)_statusCode >= 400)
        {
            string preview;
            try
            {
                var buf = _responseBody.ToArray();
                preview = System.Text.Encoding.UTF8.GetString(buf, 0, Math.Min(buf.Length, 4096));
            }
            catch
            {
                preview = string.Empty;
            }
            throw new WebException(
                $"The remote server returned an error: ({(int)_statusCode}) {_statusCode}. {preview}",
                null,
                WebExceptionStatus.ProtocolError,
                null);
        }
    }

    public override string RequestContentType
    {
        get => _contentType;
        set => _contentType = value;
    }

    public override string RequestMethod
    {
        get => _method;
        set => _method = value ?? "GET";
    }

    public override bool RequestKeepAlive
    {
        get => _keepAlive;
        set => _keepAlive = value;
    }

    public override WebHeaderCollection RequestHeaders => _requestHeaders;
    public override WebHeaderCollection ResponseHeaders => _responseHeaders;

    public override HttpWebRequest WebRequest
    {
        get
        {
            if (_legacyWebRequest == null)
            {
                // Build a detached HttpWebRequest so callers that read its properties
                // (User-Agent, Method, etc.) see something consistent. The request is
                // never executed; the real wire call goes through HttpClient above.
#pragma warning disable SYSLIB0014
                _legacyWebRequest = (HttpWebRequest)System.Net.WebRequest.Create(_url);
#pragma warning restore SYSLIB0014
                try { _legacyWebRequest.Method = _method; } catch { }
            }
            return _legacyWebRequest;
        }
    }

    public override HttpStatusCode StatusCode => _statusCode;
    public override string ResponseContentType => _responseContentType;

    public override void Dispose()
    {
        _response?.Dispose();
        _responseBody?.Dispose();
        _requestBody?.Dispose();
    }
}

public sealed class HttpClientExecutorFactory : WebRequestExecutorFactory
{
    public override WebRequestExecutor CreateWebRequestExecutor(ClientRuntimeContext context, string requestUrl)
    {
        return new HttpClientExecutor(requestUrl);
    }
}
