[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [Alias('Quipu')]
    [string] $Knotlog
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Fail([string] $Message) {
    [Console]::Error.WriteLine("Knotlog hook repair failed: $Message")
    exit 1
}

$script = Join-Path $PSScriptRoot 'repair-hooks'
if (-not (Test-Path -LiteralPath $script -PathType Leaf)) {
    Fail "vault repair entrypoint is missing: $script"
}

$bashCommand = Get-Command bash.exe -ErrorAction SilentlyContinue
$bash = $null
if ($null -ne $bashCommand) {
    $bash = $bashCommand.Source
}
if ([String]::IsNullOrWhiteSpace($bash)) {
    $roots = @()
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not [String]::IsNullOrWhiteSpace($base)) {
            $roots += (Join-Path $base 'Git')
        }
    }
    foreach ($key in @(
        'HKCU:\SOFTWARE\GitForWindows',
        'HKLM:\SOFTWARE\GitForWindows',
        'HKLM:\SOFTWARE\WOW6432Node\GitForWindows'
    )) {
        $props = Get-ItemProperty -LiteralPath $key -Name InstallPath -ErrorAction SilentlyContinue
        if ($null -ne $props -and -not [String]::IsNullOrWhiteSpace($props.InstallPath)) {
            $roots += $props.InstallPath
        }
    }
    foreach ($root in $roots) {
        foreach ($suffix in @('bin\bash.exe', 'usr\bin\bash.exe')) {
            $candidate = Join-Path $root $suffix
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $bash = (Resolve-Path -LiteralPath $candidate).Path
                break
            }
        }
        if (-not [String]::IsNullOrWhiteSpace($bash)) {
            break
        }
    }
}
if ([String]::IsNullOrWhiteSpace($bash)) {
    Fail 'Git for Windows bash.exe was not found on PATH or in standard install locations'
}

& $bash $script --knotlog $Knotlog
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
