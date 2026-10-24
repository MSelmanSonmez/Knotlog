[CmdletBinding()]
param(
    [switch] $DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Fail([string] $Message) {
    [Console]::Error.WriteLine("Knotlog uninstall failed: $Message")
    exit 1
}

# This removes exactly what install.ps1 created outside the vault: the two
# command shims under %LOCALAPPDATA%\Knotlog\bin and the user PATH entry that
# points at them. It never touches the vault -- those are the user's notes,
# and deleting them has to stay a deliberate, separate act.

# An install from before the rename lives under %LOCALAPPDATA%\Quipu\bin; it
# is ours too and is cleaned the same way.
$bins = @(
    (Join-Path $env:LOCALAPPDATA 'Knotlog\bin'),
    (Join-Path $env:LOCALAPPDATA 'Quipu\bin')
)
$removed = 0

# Only remove a shim we can recognize as ours. A foreign file sitting at that
# path is reported, never deleted -- the same rule the POSIX `knotlog uninstall`
# follows for a stranger's command on PATH.
foreach ($bin in $bins) {
    # v3 writes knotlog.cmd + knotlog; an install from before the rename wrote
    # quipu.cmd + quipu. Both pairs are ours, in either directory.
    $shims = @((Join-Path $bin 'knotlog.cmd'), (Join-Path $bin 'quipu.cmd'))
    $posixShims = @((Join-Path $bin 'knotlog'), (Join-Path $bin 'quipu'))
    foreach ($path in @($shims + $posixShims)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            continue
        }
        $text = [IO.File]::ReadAllText($path)
        $isOurs = $false
        $name = [IO.Path]::GetFileNameWithoutExtension($path)
        if ($path.EndsWith('.cmd')) {
            # install.ps1 writes: @echo off / "<bash>" "<checkout>\knotlog" %*
            $isOurs = ($text -match '(?m)^@echo off') -and ($text -match 'knotlog|quipu')
        } else {
            $normalized = $text -replace "`r`n", "`n"
            # install.ps1 builds this from a @'...'@ here-string, which does NOT
            # carry a trailing newline -- the shim on disk is exactly 47 bytes and
            # ends at the closing quote. Compare against that shape, and tolerate a
            # trailing newline in case some editor added one.
            $expected = "#!/bin/sh`nexec `"`$(dirname `"`$0`")/$name.cmd`" `"`$@`""
            $isOurs = (($normalized -eq $expected) -or ($normalized -eq "$expected`n"))
        }
        if (-not $isOurs) {
            Write-Output "Left in place: $path is not a Knotlog shim - remove it yourself if you want it gone"
            continue
        }
        if ($DryRun) {
            Write-Output "Would remove: $path"
        } else {
            Remove-Item -LiteralPath $path -Force
            Write-Output "Removed: $path"
        }
        $removed++
    }
}

if ($removed -eq 0) {
    Write-Output 'Command: nothing to remove; no Knotlog shim found'
}

# Drop a bin directory only when it is ours and now empty; a directory the
# user put something else in stays.
foreach ($bin in $bins) {
    if ((-not $DryRun) -and (Test-Path -LiteralPath $bin -PathType Container)) {
        if (@(Get-ChildItem -LiteralPath $bin -Force).Count -eq 0) {
            Remove-Item -LiteralPath $bin -Force
            Write-Output "Removed: $bin (empty)"
        }
    }
}

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$parts = @()
if ($null -ne $userPath -and $userPath.Length -gt 0) {
    $parts = @($userPath -split ';' | Where-Object { $_.Length -gt 0 })
}
$isOurBin = {
    param([string] $entry)
    $part = $entry.TrimEnd('\')
    @($bins | Where-Object { [StringComparer]::OrdinalIgnoreCase.Equals($part, $_.TrimEnd('\')) }).Count -gt 0
}
$kept = @($parts | Where-Object { -not (& $isOurBin $_) })
$dropped = @($parts | Where-Object { & $isOurBin $_ })
if ($kept.Count -ne $parts.Count) {
    if ($DryRun) {
        Write-Output "Would remove from user PATH: $($dropped -join ', ')"
    } else {
        [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'User')
        Write-Output "Removed from user PATH: $($dropped -join ', ') (restart the shell to refresh PATH)"
    }
} else {
    Write-Output 'User PATH: no Knotlog entry found'
}

Write-Output ''
Write-Output 'Your vault was not touched. To see what is left inside it, or to'
Write-Output 'remove the vault too, open the vault folder - it is still exactly'
Write-Output 'where install put it.'
