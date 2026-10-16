using System;
using System.Reflection;
using System.Runtime.ExceptionServices;
using System.Threading.Tasks;

namespace SPOService.CrossPlatform;

// Why this exists:
// Microsoft.Online.SharePoint.PowerShell.OAuthSession.SignIn(string) is declared
// async but contains no await. Its state machine does Task.Run(...).Result with a
// 90-second cancellation timer, so it blocks the calling thread for the whole
// interactive sign-in and returns an already-completed Task. PowerShell cannot
// interrupt a blocked .NET call, so Ctrl+C would only be honoured once the vendor
// gave up. Invoking the reflected method on the thread pool hands the PowerShell
// thread a task it can poll with an interruptible sleep (Wait-SPOAuthenticationTask).
//
// After Ctrl+C the vendor's thread keeps running until its own timeout; nothing
// here can cancel it because the vendor API exposes no cancellation token. That
// limitation is documented in the module help.
public static class BackgroundInvoker
{
    public static Task<object> InvokeAsync(MethodInfo method, object target, object[] arguments)
    {
        ArgumentNullException.ThrowIfNull(method);

        return Task.Run(() =>
        {
            try
            {
                return method.Invoke(target, arguments);
            }
            catch (TargetInvocationException ex) when (ex.InnerException is not null)
            {
                // Surface the vendor's real exception type, with its stack, rather
                // than the reflection wrapper.
                ExceptionDispatchInfo.Capture(ex.InnerException).Throw();
                throw; // unreachable; satisfies the compiler
            }
        });
    }
}
