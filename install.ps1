[CmdletBinding()]
param(
    [switch] $Force,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $QuipuArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Fail([string] $Message) {
    [Console]::Error.WriteLine("Knotlog install failed: $Message")
    exit 1
}

$repo = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$knotlog = Join-Path $repo 'knotlog'
if (-not (Test-Path -LiteralPath $knotlog -PathType Leaf)) {
    Fail "the checkout does not contain '$knotlog'"
}

# PowerShell may start bash.exe without a POSIX tty, in which case knotlog's
# own wizard cannot ask anything and would reach the non-interactive path
# with no --user and fail before creating anything; when a real tty is
# available (as it is on a normal console), knotlog's own wizard prompts too
# (location, then identity) after this script hands off to it. Either way,
# language must be the first question asked, matching knotlog's own "language
# is the first interaction" rule -- collect it here, before user name, so
# neither this script's own prompt nor knotlog's downstream wizard displays
# out of order. Callers using --no-prompt/--lang/--user remain fully explicit.
$forward = @()
if ($null -ne $QuipuArguments) {
    $forward = @($QuipuArguments)
}
$hasNoPrompt = $false
$hasUser = $false
$hasLang = $false
for ($i = 0; $i -lt $forward.Count; $i++) {
    if ($forward[$i] -eq '--no-prompt') {
        $hasNoPrompt = $true
    } elseif ($forward[$i] -eq '--user') {
        $hasUser = $true
        $i++
    } elseif ($forward[$i] -eq '--lang') {
        $hasLang = $true
        $i++
    }
}

# [Console]::WindowWidth throws (or is meaningless) without a real console
# -- input/output redirected, no console host -- so this is a best-effort
# probe: fall back to 80 (the safe default knotlog's own POSIX side also
# uses) on any failure, same fallback contract as everywhere else here.
function Get-TerminalWidth {
    try {
        $w = [Console]::WindowWidth
        if ($w -gt 0) { return $w }
    } catch { }
    return 80
}

# Draws an ASCII box (no Unicode box-drawing characters -- those risk a
# codepage mismatch in a Windows console) around the given lines, sized to
# the widest one, capped at min(detected terminal width, 76) total columns
# but never shrunk below 40 -- same cap, floor, and reasoning as knotlog's
# own POSIX box: a long vault path would otherwise stretch past 80 columns
# and wrap on a standard console, and a genuinely narrow/undetectable
# console must not be allowed to crush the box below usefulness either. A
# line still over the cap is elided from the FRONT with a leading "..."
# (the tail of a path is the informative end); nothing is lost, the
# install summary prints the full path again later, outside any box. Only
# lines from index $ProtectFirst onward (default 2: header + title, the
# "[n/N] Title" step counter this whole box exists to keep honest) are
# eligible for eliding -- those two must survive intact no matter how
# narrow the cap ends up. .NET's [string]::Length counts UTF-16 code
# units, which for every character this script ever prints (ASCII plus
# the Turkish ş/ç/ü/ğ/ö/ı, all single BMP code points, no surrogate
# pairs) is exactly the display-column width -- so both the alignment and
# the truncation point land on real character boundaries, never
# mid-character.
function Write-Box([string[]] $Lines, [int] $ProtectFirst = 2) {
    $cap = [Math]::Min((Get-TerminalWidth), 76)
    if ($cap -lt 40) { $cap = 40 }
    $contentMax = $cap - 4
    if ($contentMax -lt 10) { $contentMax = 10 }
    $elided = for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($i -ge $ProtectFirst -and $line.Length -gt $contentMax) {
            $keep = $contentMax - 3
            if ($keep -lt 1) { $keep = 1 }
            '...' + $line.Substring($line.Length - $keep)
        } else {
            $line
        }
    }
    $width = ($elided | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
    $border = '+' + ('-' * ($width + 2)) + '+'
    Write-Host $border
    foreach ($line in $elided) {
        Write-Host ('| ' + $line.PadRight($width) + ' |')
    }
    Write-Host $border
}

# Shipped languages = the i18n/<code>.txt files of this checkout, en first
# (the same rule as knotlog's _q_langs). Names are display labels only.
$langNames = @{ en = 'English'; tr = 'Turkish'; es = 'Spanish'; 'pt-br' = 'Portuguese (Brazil)'; ja = 'Japanese'; 'zh-cn' = 'Chinese (Simplified)' }
$langCodes = @('en') + @(Get-ChildItem -LiteralPath (Join-Path $repo 'i18n') -Filter '*.txt' | ForEach-Object { $_.BaseName } | Where-Object { $_ -ne 'en' })

# Arrow-key language menu, mirroring knotlog's own POSIX install wizard. This
# is a strict optional upgrade over the Read-Host prompt below it: ReadKey
# throws whenever there is no real interactive console (input redirected, a
# pipe, a non-console host), so the try/catch here is the whole fallback --
# any such failure returns $null and the caller falls straight through to
# the original Read-Host question, unchanged. The screen is deliberately
# bare here -- no header, no question line, no hint line, no box -- and
# both option labels stay in English regardless of which one is picked,
# since the language is not chosen yet (matches knotlog's own POSIX menu).
function Read-LanguageMenu {
    $options = $langCodes
    $labels = @($langCodes | ForEach-Object { if ($langNames.ContainsKey($_)) { "$_ -- $($langNames[$_])" } else { $_ } })
    $sel = 0
    try {
        if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
            throw 'no interactive console'
        }
        while ($true) {
            Clear-Host
            Write-Host 'Language'
            Write-Host ''
            for ($i = 0; $i -lt $options.Count; $i++) {
                if ($i -eq $sel) {
                    Write-Host "> $($labels[$i])"
                } else {
                    Write-Host "  $($labels[$i])"
                }
            }
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow'   { $sel = ($sel - 1 + $options.Count) % $options.Count }
                'DownArrow' { $sel = ($sel + 1) % $options.Count }
                'Enter'     { return $options[$sel] }
                default     { }
            }
        }
    } catch {
        return $null
    }
}

$lang = 'en'
if ($hasLang) {
    $langIndex = [Array]::IndexOf($forward, '--lang')
    $lang = $forward[$langIndex + 1]
} elseif (-not $hasNoPrompt) {
    $lang = Read-LanguageMenu
    if ($null -eq $lang) {
        $langPrompt = "Language / Dil ($($langCodes -join '/'))"
        $langAns = "$(Read-Host $langPrompt)".Trim().ToLower().Replace('_', '-')
        if ([String]::IsNullOrWhiteSpace($langAns)) {
            $lang = 'en'
        } elseif ($langCodes -contains $langAns) {
            $lang = $langAns
        } else {
            Fail "unrecognized language '$langAns'; answer one of: $($langCodes -join ', ')"
        }
    }
    $forward += @('--lang', $lang)
}

# Live Windows run (found by the maintainer): once language was answered, the name
# question printed right under the leftover menu/prompt lines, then handed
# off to knotlog's own bash wizard, which opened with a stale "[1/4]
# Language: tr" page for a question already answered here -- two wizards'
# seam, visible to the user. Clearing here makes the name question read as
# the next page of ONE wizard; KNOTLOG_INSTALL_HANDOFF below (set only when
# language was actually asked/forwarded by this script) tells knotlog's own
# wizard to skip its language page and renumber what's left honestly.
if (-not $hasNoPrompt -and -not $hasUser) {
    try { Clear-Host } catch { }
    $header = if ($lang -eq 'tr') { 'Knotlog kurulumu' } else { 'Knotlog setup' }
    $title = if ($lang -eq 'tr') { 'Kimlik' } else { 'Identity' }
    $langLabel = if ($lang -eq 'tr') { 'Dil' } else { 'Language' }
    Write-Box @($header, $title, "${langLabel}: $lang")
    Write-Host ''
    $userPrompt = if ($lang -eq 'tr') { 'Adın' } else { 'Your name' }
    $user = Read-Host $userPrompt
    if ([String]::IsNullOrWhiteSpace($user)) {
        Fail 'a user name is required; rerun with --user NAME'
    }
    $forward += @('--user', $user)
}

function Find-GitExecutable([string] $Name) {
    $command = Get-Command "$Name.exe" -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    # PowerShell may inherit a stale or restricted PATH. Check the standard
    # Git for Windows roots and its registry install paths without elevation.
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

    $relative = if ($Name -eq 'bash') {
        @('bin\bash.exe', 'usr\bin\bash.exe')
    } else {
        @('cmd\git.exe', 'bin\git.exe')
    }
    foreach ($root in $roots) {
        foreach ($suffix in $relative) {
            $candidate = Join-Path $root $suffix
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return (Resolve-Path -LiteralPath $candidate).Path
            }
        }
    }
    return $null
}

$git = Find-GitExecutable 'git'
$bash = Find-GitExecutable 'bash'
if ([String]::IsNullOrWhiteSpace($git) -or [String]::IsNullOrWhiteSpace($bash)) {
    Fail 'Git for Windows is required; install it from https://git-scm.com/download/win and retry'
}

# Tells knotlog's own wizard it is being driven from this script -- skip its
# language page (this script already showed language, whether via the menu
# or the fallback question, or the caller passed --lang directly) and
# renumber whatever pages are left honestly. Not a documented public flag.
$env:KNOTLOG_INSTALL_HANDOFF = '1'
& $bash $knotlog 'install' '--no-link' @forward
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$bin = Join-Path $env:LOCALAPPDATA 'Knotlog\bin'
$shim = Join-Path $bin 'knotlog.cmd'
New-Item -ItemType Directory -Force -Path $bin | Out-Null

$bashForCmd = $bash.Replace('%', '%%')
$knotlogForCmd = $knotlog.Replace('%', '%%')
$shimText = "@echo off`r`n`"$bashForCmd`" `"$knotlogForCmd`" %*`r`n"
if (Test-Path -LiteralPath $shim -PathType Leaf) {
    $existing = [IO.File]::ReadAllText($shim)
    if ($existing -ne $shimText) {
        # A stale knotlog shim (another checkout) may be replaced on -Force or
        # a yes; any other file is never ours to overwrite.
        $ours = $existing -like '@echo off*knotlog*%*'
        $replace = $false
        if ($ours -and $Force) {
            $replace = $true
        } elseif ($ours -and -not $hasNoPrompt) {
            try { $replace = (Read-Host "$shim points at another Knotlog checkout. Replace it? [y/N]") -match '^(y|yes)$' } catch { }
        }
        if (-not $replace) {
            if ($ours) { Fail "an existing command shim points elsewhere: $shim. Rerun with -Force to replace it, or remove it yourself." }
            Fail "$shim is not a shim Knotlog made; it is never replaced. Remove it yourself."
        }
        [IO.File]::WriteAllText($shim, $shimText, [Text.Encoding]::ASCII)
    }
} else {
    [IO.File]::WriteAllText($shim, $shimText, [Text.Encoding]::ASCII)
}

# Git Bash does not apply Windows PATHEXT lookup to bare commands. Keep the
# required .cmd shim for PowerShell/cmd.exe, and add a tiny executable POSIX
# shim so Claude's `shell: bash` hooks can resolve `knotlog` after PATH refresh.
$posixShim = Join-Path $bin 'knotlog'
$posixShimText = @'
#!/bin/sh
exec "$(dirname "$0")/knotlog.cmd" "$@"
'@
# The here-string above carries install.ps1's own on-disk line endings.
# .gitattributes pins *.ps1 to eol=crlf, so this file checks out CRLF on
# every machine regardless of core.autocrlf -- but the POSIX shim itself
# must always be LF -- it is a shebang script executed by Git Bash, and a
# stray CR before `exec` risks breaking the shebang line on some sh
# implementations. Normalize unconditionally (defense in depth: this must
# hold even if the .gitattributes rule is ever removed or a checkout
# predates it) so the written file is LF regardless of how this script was
# checked out.
$posixShimText = $posixShimText -replace "`r`n", "`n"
if (Test-Path -LiteralPath $posixShim -PathType Leaf) {
    $existing = [IO.File]::ReadAllText($posixShim)
    # Compare on normalized (LF) content so a shim written by an earlier,
    # CRLF-tainted install (or checked out on a different autocrlf setting)
    # is recognized as the same script rather than tripping the "foreign
    # file" guard below. Bytes-identical-after-normalization means it is our
    # shim -- silently rewrite it as LF so re-running install self-heals
    # instead of failing after the vault has already been created. Only a
    # genuine content mismatch (a different tool's shim at this path) still
    # fails.
    $existingNormalized = $existing -replace "`r`n", "`n"
    if ($existingNormalized -ne $posixShimText) {
        Fail "$posixShim is not a shim Knotlog made; it is never replaced. Remove it yourself."
    } elseif ($existing -ne $posixShimText) {
        [IO.File]::WriteAllText($posixShim, $posixShimText, [Text.Encoding]::ASCII)
    }
} else {
    [IO.File]::WriteAllText($posixShim, $posixShimText, [Text.Encoding]::ASCII)
}
$posixPath = $posixShim -replace '\\', '/'
if ($posixPath -match '^[A-Za-z]:/') {
    $posixPath = '/' + $posixPath.Substring(0, 1).ToLowerInvariant() + $posixPath.Substring(2)
}
$bashDir = Split-Path $bash -Parent
$gitRoot = Split-Path $bashDir -Parent
$chmod = Join-Path $gitRoot 'usr\bin\chmod.exe'
if (-not (Test-Path -LiteralPath $chmod -PathType Leaf)) {
    Fail "Git for Windows chmod is missing: $chmod"
}
& $chmod '+x' '--' $posixPath
if ($LASTEXITCODE -ne 0) {
    Fail "could not mark the Bash command shim executable: $posixShim"
}

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$parts = @()
if ($null -ne $userPath -and $userPath.Length -gt 0) {
    $parts = @($userPath -split ';' | Where-Object { $_.Length -gt 0 })
}
$hasBin = $false
foreach ($part in $parts) {
    if ([StringComparer]::OrdinalIgnoreCase.Equals($part.TrimEnd('\'), $bin.TrimEnd('\'))) {
        $hasBin = $true
        break
    }
}
if (-not $hasBin) {
    $newPath = (($parts + $bin) -join ';')
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    if (-not (($env:Path -split ';') | Where-Object { [StringComparer]::OrdinalIgnoreCase.Equals($_.TrimEnd('\'), $bin.TrimEnd('\')) })) {
        $env:Path = "$env:Path;$bin"
    }
}

Write-Output "Command shim: $shim"
Write-Output 'User PATH: Knotlog\bin is ready (restart the shell to refresh PATH)'
