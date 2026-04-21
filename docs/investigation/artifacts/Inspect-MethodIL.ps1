param(
    [Parameter(Mandatory = $true)]
    [string]$AssemblyPath,

    [Parameter(Mandatory = $true)]
    [string]$TypeName,

    [Parameter(Mandatory = $true)]
    [string]$MethodName,

    [int]$OverloadIndex = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-OpcodeMap {
    $map = @{}
    foreach ($field in [System.Reflection.Emit.OpCodes].GetFields([System.Reflection.BindingFlags]'Public,Static')) {
        $opcode = [System.Reflection.Emit.OpCode]$field.GetValue($null)
        $key = ([int]$opcode.Value) -band 0xFFFF
        $map[$key] = $opcode
    }
    return $map
}

function Resolve-TokenOperand {
    param(
        [System.Reflection.Module]$Module,
        [int]$Token,
        [System.Reflection.Emit.OperandType]$OperandType,
        [Type[]]$GenericTypeArguments,
        [Type[]]$GenericMethodArguments
    )

    try {
        switch ($OperandType) {
            ([System.Reflection.Emit.OperandType]::InlineMethod) {
                return $Module.ResolveMethod($Token, $GenericTypeArguments, $GenericMethodArguments)
            }
            ([System.Reflection.Emit.OperandType]::InlineField) {
                return $Module.ResolveField($Token, $GenericTypeArguments, $GenericMethodArguments)
            }
            ([System.Reflection.Emit.OperandType]::InlineType) {
                return $Module.ResolveType($Token, $GenericTypeArguments, $GenericMethodArguments)
            }
            ([System.Reflection.Emit.OperandType]::InlineTok) {
                try {
                    return $Module.ResolveMember($Token, $GenericTypeArguments, $GenericMethodArguments)
                }
                catch {
                    return "token 0x{0:x8}" -f $Token
                }
            }
            ([System.Reflection.Emit.OperandType]::InlineString) {
                return ('"{0}"' -f $Module.ResolveString($Token))
            }
            ([System.Reflection.Emit.OperandType]::InlineSig) {
                return "signature 0x{0:x8}" -f $Token
            }
            default {
                return "token 0x{0:x8}" -f $Token
            }
        }
    }
    catch {
        return "unresolved token 0x{0:x8}" -f $Token
    }
}

function Read-Operand {
    param(
        [byte[]]$Bytes,
        [int]$Position,
        [System.Reflection.Emit.OpCode]$Opcode,
        [System.Reflection.Module]$Module,
        [Type[]]$GenericTypeArguments,
        [Type[]]$GenericMethodArguments
    )

    $operandType = $Opcode.OperandType
    $next = $Position

    switch ($operandType) {
        ([System.Reflection.Emit.OperandType]::InlineNone) {
            return @{
                Operand = $null
                Next = $next
            }
        }
        ([System.Reflection.Emit.OperandType]::ShortInlineBrTarget) {
            $delta = [int]$Bytes[$next]
            if ($delta -ge 128) {
                $delta -= 256
            }
            $next += 1
            return @{
                Operand = ('IL_{0:x4}' -f ($next + $delta))
                Next = $next
            }
        }
        ([System.Reflection.Emit.OperandType]::InlineBrTarget) {
            $delta = [BitConverter]::ToInt32($Bytes, $next)
            $next += 4
            return @{
                Operand = ('IL_{0:x4}' -f ($next + $delta))
                Next = $next
            }
        }
        ([System.Reflection.Emit.OperandType]::ShortInlineI) {
            $value = [int]$Bytes[$next]
            if ($value -ge 128) {
                $value -= 256
            }
            $next += 1
            return @{
                Operand = $value
                Next = $next
            }
        }
        ([System.Reflection.Emit.OperandType]::InlineI) {
            $value = [BitConverter]::ToInt32($Bytes, $next)
            $next += 4
            return @{
                Operand = $value
                Next = $next
            }
        }
        ([System.Reflection.Emit.OperandType]::InlineI8) {
            $value = [BitConverter]::ToInt64($Bytes, $next)
            $next += 8
            return @{
                Operand = $value
                Next = $next
            }
        }
        ([System.Reflection.Emit.OperandType]::ShortInlineR) {
            $value = [BitConverter]::ToSingle($Bytes, $next)
            $next += 4
            return @{
                Operand = $value
                Next = $next
            }
        }
        ([System.Reflection.Emit.OperandType]::InlineR) {
            $value = [BitConverter]::ToDouble($Bytes, $next)
            $next += 8
            return @{
                Operand = $value
                Next = $next
            }
        }
        ([System.Reflection.Emit.OperandType]::ShortInlineVar) {
            $value = $Bytes[$next]
            $next += 1
            return @{
                Operand = "V_$value"
                Next = $next
            }
        }
        ([System.Reflection.Emit.OperandType]::InlineVar) {
            $value = [BitConverter]::ToUInt16($Bytes, $next)
            $next += 2
            return @{
                Operand = "V_$value"
                Next = $next
            }
        }
        ([System.Reflection.Emit.OperandType]::InlineSwitch) {
            $count = [BitConverter]::ToInt32($Bytes, $next)
            $next += 4
            $targets = for ($i = 0; $i -lt $count; $i++) {
                $delta = [BitConverter]::ToInt32($Bytes, $next)
                $next += 4
                'IL_{0:x4}' -f ($next + $delta)
            }
            return @{
                Operand = ($targets -join ', ')
                Next = $next
            }
        }
        default {
            $token = [BitConverter]::ToInt32($Bytes, $next)
            $next += 4
            return @{
                Operand = (Resolve-TokenOperand -Module $Module -Token $token -OperandType $operandType -GenericTypeArguments $GenericTypeArguments -GenericMethodArguments $GenericMethodArguments)
                Next = $next
            }
        }
    }
}

$assembly = [Reflection.Assembly]::LoadFrom($AssemblyPath)
$type = $assembly.GetType($TypeName, $true, $false)
$methods =
    if ($MethodName -eq '.ctor') {
        $type.GetConstructors([System.Reflection.BindingFlags]'Public,NonPublic,Instance,DeclaredOnly')
    }
    else {
        $type.GetMethods([System.Reflection.BindingFlags]'Public,NonPublic,Static,Instance,DeclaredOnly') |
            Where-Object Name -eq $MethodName
    }

if (-not $methods) {
    throw "Method not found: $TypeName::$MethodName"
}

$selected = @($methods)[$OverloadIndex]
if (-not $selected) {
    throw "Overload index $OverloadIndex is out of range for $TypeName::$MethodName"
}

$body = $selected.GetMethodBody()
if (-not $body) {
    throw "Method body unavailable for $($selected)"
}

$bytes = $body.GetILAsByteArray()
$module = $selected.Module
$genericTypeArguments = if ($type.IsGenericType) { $type.GetGenericArguments() } else { [Type[]]@() }
$genericMethodArguments = if ($selected.IsGenericMethod) { $selected.GetGenericArguments() } else { [Type[]]@() }
$opcodes = Get-OpcodeMap

"Method: $selected"
"MaxStack: $($body.MaxStackSize)"
"Locals:"
for ($i = 0; $i -lt $body.LocalVariables.Count; $i++) {
    "  [$i] $($body.LocalVariables[$i].LocalType.FullName)"
}
"Instructions:"

$position = 0
while ($position -lt $bytes.Length) {
    $offset = $position
    $raw = [int]$bytes[$position]
    $position += 1
    if ($raw -eq 0xFE) {
        $raw = ($raw -shl 8) -bor [int]$bytes[$position]
        $position += 1
    }

    $opcode = $opcodes[$raw]
    if (-not $opcode) {
        throw ('Unknown opcode 0x{0:x4} at IL_{1:x4}' -f $raw, $offset)
    }

    $operandInfo = Read-Operand -Bytes $bytes -Position $position -Opcode $opcode -Module $module -GenericTypeArguments $genericTypeArguments -GenericMethodArguments $genericMethodArguments
    $position = $operandInfo.Next

    if ($null -ne $operandInfo.Operand -and $operandInfo.Operand -ne '') {
        '{0} {1,-14} {2}' -f ('IL_{0:x4}:' -f $offset), $opcode.Name, $operandInfo.Operand
    }
    else {
        '{0} {1}' -f ('IL_{0:x4}:' -f $offset), $opcode.Name
    }
}
