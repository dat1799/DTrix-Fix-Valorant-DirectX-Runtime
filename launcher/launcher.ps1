#Requires -Version 5.1
<#
.SYNOPSIS
    DTrix DirectX Tool - Launcher
    Downloads, verifies and executes check-directx.ps1 from GitHub.

.DESCRIPTION
    One-line install:
        irm "https://gist.githubusercontent.com/dat1799/GIST_ID/raw/launcher.ps1" | iex

    Security flow:
        1. Download manifest.json  (HTTPS only)
        2. Validate manifest structure
        3. Check launcher version compatibility
        4. Download payload         (HTTPS only)
        5. Verify SHA-256 hash      (vs manifest)
        6. Verify Authenticode      (if RequireSignature = true)
        7. Execute via PowerShell -File  (NOT Invoke-Expression)
        8. Clean up temp files

.NOTES
    SECURITY LIMITS (read before distributing):
    - SHA-256 ensures INTEGRITY (file not tampered). Does NOT hide source.
    - Authenticode ensures AUTHENTICITY (came from you). Does NOT hide source.
    - Any .ps1 file that runs on the user's machine can be read by that user.
    - There is no way to fully hide PowerShell source at runtime. This is an
      architectural limit, not a design flaw.
#>

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

# ─────────────────────────────────────────────
# CONFIG - Update before publishing to Gist
# ─────────────────────────────────────────────
$script:CONFIG = @{
    ManifestUrl      = 'https://raw.githubusercontent.com/dat1799/Check-Valorant-DirectX-Runtime/main/manifest/manifest.json'
    ToolName         = 'DTrix DirectX Tool'
    LauncherVersion  = '1.0.0'
    DownloadTimeout  = 60
    RequireSignature = $false
    ExpectedSigner   = 'DTrix Team'
    TempDir          = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'DTrixLauncher')
}

# ─────────────────────────────────────────────
# UI HELPERS
# ─────────────────────────────────────────────
function Write-Logo {
    $logo = @'

    ██████╗ ████████╗██████╗ ██╗██╗  ██╗
    ██╔══██╗╚══██╔══╝██╔══██╗██║╚██╗██╔╝
    ██║  ██║   ██║   ██████╔╝██║ ╚███╔╝
    ██║  ██║   ██║   ██╔══██╗██║ ██╔██╗
    ██████╔╝   ██║   ██║  ██║██║██╔╝ ██╗
    ╚═════╝    ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝
         DirectX System Integrity Tool
'@
    Write-Host $logo -ForegroundColor Cyan
    Write-Host "  Launcher v$($script:CONFIG.LauncherVersion)  |  $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor DarkGray
    Write-Host ('-' * 52) -ForegroundColor DarkGray
    Write-Host ''
}

function Write-SectionHeader { param([string]$Title)
    Write-Host ''
    Write-Host "  [$Title]" -ForegroundColor DarkCyan
}
function Write-OK   { param([string]$m) Write-Host "  [OK]   $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Write-Fail { param([string]$m) Write-Host "  [FAIL] $m" -ForegroundColor Red }
function Write-Info { param([string]$m) Write-Host "  [INFO] $m" -ForegroundColor Cyan }

# ─────────────────────────────────────────────
# TLS
# ─────────────────────────────────────────────
function Set-SecureTls {
    try {
        [Net.ServicePointManager]::SecurityProtocol = `
            [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    }
    catch {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }
}

# ─────────────────────────────────────────────
# DOWNLOAD (HTTPS enforced, with retry)
# ─────────────────────────────────────────────
function Invoke-SecureDownload {
    param(
        [string]$Url,
        [string]$Destination,
        [string]$Label      = 'file',
        [int]   $RetryCount = 3
    )

    if ($Url -notmatch '^https://') {
        throw "URL must use HTTPS. Rejected: $Url"
    }

    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        try {
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add('User-Agent', "DTrix-Launcher/$($script:CONFIG.LauncherVersion)")
            $wc.Headers.Add('Cache-Control', 'no-cache')
            $wc.Proxy = [System.Net.WebRequest]::DefaultWebProxy
            $wc.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials

            Write-Host "  Downloading $Label ..." -NoNewline -ForegroundColor DarkGray
            $wc.DownloadFile($Url, $Destination)
            $wc.Dispose()
            Write-Host " done" -ForegroundColor Green
            return
        }
        catch {
            if ($attempt -lt $RetryCount) {
                Write-Warn "Attempt $attempt failed: $($_.Exception.Message). Retrying..."
                Start-Sleep -Seconds (2 * $attempt)
            }
            else {
                throw
            }
        }
    }
}

# ─────────────────────────────────────────────
# VERIFICATION
# ─────────────────────────────────────────────
function Test-PayloadHash {
    param([string]$FilePath, [string]$ExpectedHash)

    if (-not (Test-Path $FilePath)) {
        Write-Fail "File not found: $FilePath"
        return $false
    }

    $actual   = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash.ToUpper()
    $expected = $ExpectedHash.ToUpper().Trim()

    if ($actual -ne $expected) {
        Write-Fail 'SHA-256 MISMATCH - payload may be tampered!'
        Write-Host "    Expected : $expected" -ForegroundColor Red
        Write-Host "    Actual   : $actual"   -ForegroundColor Red
        return $false
    }
    Write-OK "SHA-256 verified: $actual"
    return $true
}

function Test-PayloadSignature {
    param([string]$FilePath)

    $sig = Get-AuthenticodeSignature -FilePath $FilePath -ErrorAction SilentlyContinue
    if ($null -eq $sig) {
        if ($script:CONFIG.RequireSignature) {
            Write-Fail 'Cannot read signature info'
            return $false
        }
        return $true
    }

    switch ($sig.Status) {
        'Valid' {
            $cn = if ($sig.SignerCertificate) {
                $sig.SignerCertificate.Subject -replace '^CN=([^,]+).*','$1'
            } else { 'Unknown' }
            Write-OK "Authenticode: $cn"
            if ($script:CONFIG.RequireSignature -and $cn -ne $script:CONFIG.ExpectedSigner) {
                Write-Fail "Publisher mismatch. Expected: $($script:CONFIG.ExpectedSigner), Got: $cn"
                return $false
            }
            return $true
        }
        'NotSigned' {
            if ($script:CONFIG.RequireSignature) {
                Write-Fail 'Payload has no digital signature. Execution refused.'
                return $false
            }
            Write-Warn 'Payload not signed (RequireSignature = false, skipped)'
            return $true
        }
        default {
            Write-Fail "Invalid signature status: $($sig.Status)"
            return $false
        }
    }
}

function Test-ManifestStructure {
    param([hashtable]$Manifest)
    $required = @('version','payloadUrl','sha256','minLauncherVersion','releaseDate')
    foreach ($field in $required) {
        if (-not $Manifest.ContainsKey($field) -or [string]::IsNullOrWhiteSpace($Manifest[$field])) {
            throw "Manifest missing required field: '$field'"
        }
    }
    if ($Manifest['payloadUrl'] -notmatch '^https://') {
        throw 'payloadUrl in manifest must use HTTPS'
    }
    if ($Manifest['sha256'] -notmatch '^[0-9A-Fa-f]{64}$') {
        throw 'sha256 in manifest is not valid (must be 64 hex chars)'
    }
}

# ─────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────
function Compare-SemVer {
    param([string]$Current, [string]$Minimum)
    try { return ([System.Version]$Current) -ge ([System.Version]$Minimum) }
    catch { return $true }
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Remove-TempDir {
    param([string]$Path)
    try {
        if (Test-Path $Path) {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    catch { }
}

# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────
function Start-Launcher {
    $tempDir  = $script:CONFIG.TempDir
    $exitCode = 0

    try {
        Clear-Host
        Write-Logo

        # -- Secure TLS ---------------------------------
        Write-SectionHeader 'Setting up secure connection'
        Set-SecureTls
        Write-OK 'TLS 1.2+ enabled'

        # -- Environment --------------------------------
        Write-SectionHeader 'Environment check'
        if (Test-IsAdmin) {
            Write-OK 'Running as Administrator'
        }
        else {
            Write-Warn 'Not running as Administrator'
            Write-Host '    -> Fix mode (-Fix) will not be available.' -ForegroundColor DarkGray
            Write-Host '    -> Scan-only mode will work.' -ForegroundColor DarkGray
        }
        $psVer = $PSVersionTable.PSVersion.ToString()
        Write-Info "PowerShell $psVer"

        # -- Download manifest --------------------------
        Write-SectionHeader 'Fetching manifest'
        Write-Info $script:CONFIG.ManifestUrl

        if (-not (Test-Path $tempDir)) {
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        }
        $manifestPath = Join-Path $tempDir 'manifest.json'
        Invoke-SecureDownload -Url $script:CONFIG.ManifestUrl -Destination $manifestPath -Label 'manifest.json'

        # Parse manifest (PS 5.1 compatible)
        $mObj = Get-Content -Path $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $mHt  = @{}
        $mObj.PSObject.Properties | ForEach-Object { $mHt[$_.Name] = $_.Value }

        Test-ManifestStructure -Manifest $mHt
        Write-OK 'Manifest structure valid'

        # -- Version info --------------------------------
        Write-SectionHeader 'Version info'
        Write-Info "Payload version : $($mHt['version'])"
        Write-Info "Release date    : $($mHt['releaseDate'])"
        if ($mHt.ContainsKey('changelog') -and $mHt['changelog']) {
            Write-Info "Changelog       : $($mHt['changelog'])"
        }

        if (-not (Compare-SemVer -Current $script:CONFIG.LauncherVersion -Minimum $mHt['minLauncherVersion'])) {
            Write-Fail "Launcher v$($script:CONFIG.LauncherVersion) is too old!"
            Write-Host "    Requires launcher >= v$($mHt['minLauncherVersion']). Please update the launcher URL." -ForegroundColor Red
            $exitCode = 2
            return
        }

        # -- Download payload ----------------------------
        Write-SectionHeader 'Downloading payload'
        $payloadUrl  = $mHt['payloadUrl']
        $payloadPath = Join-Path $tempDir 'check-directx.ps1'

        Write-Info $payloadUrl
        Invoke-SecureDownload -Url $payloadUrl -Destination $payloadPath -Label 'check-directx.ps1'

        $sizekb = [math]::Round((Get-Item $payloadPath).Length / 1KB, 1)
        Write-OK "Downloaded ($sizekb KB)"

        # -- Integrity verification ---------------------
        Write-SectionHeader 'Integrity verification'

        $hashOK = Test-PayloadHash -FilePath $payloadPath -ExpectedHash $mHt['sha256']
        if (-not $hashOK) {
            Write-Fail 'VERIFICATION FAILED - payload may be forged or corrupted!'
            Write-Host '    -> Script will NOT be executed.' -ForegroundColor Red
            Write-Host '    -> If you trust the source, try re-running.' -ForegroundColor Yellow
            $exitCode = 3
            return
        }

        $sigOK = Test-PayloadSignature -FilePath $payloadPath
        if (-not $sigOK) {
            Write-Fail 'SIGNATURE VERIFICATION FAILED - execution refused!'
            $exitCode = 4
            return
        }

        # -- Execute ------------------------------------
        Write-SectionHeader 'Executing payload'
        Write-OK 'All integrity checks passed'
        Write-Info "Starting $($script:CONFIG.ToolName)..."
        Write-Host ''
        Write-Host ('-' * 52) -ForegroundColor DarkGray

        $psExe    = if ($PSVersionTable.PSVersion.Major -ge 6) { 'pwsh' } else { 'powershell' }
        $procArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$payloadPath`"")
        $proc     = Start-Process -FilePath $psExe -ArgumentList $procArgs -Wait -PassThru

        Write-Host ''
        Write-Host ('-' * 52) -ForegroundColor DarkGray

        if ($proc.ExitCode -eq 0) {
            Write-OK "Completed (exit code: 0)"
        }
        else {
            Write-Warn "Exited with code: $($proc.ExitCode)"
        }

    }
    catch [System.Net.WebException] {
        Write-Host ''
        Write-Fail "Network error: $($_.Exception.Message)"
        Write-Host '    -> Check your internet connection and try again.' -ForegroundColor Yellow
        $exitCode = 10
    }
    catch [System.UnauthorizedAccessException] {
        Write-Host ''
        Write-Fail "Access denied: $($_.Exception.Message)"
        Write-Host '    -> Try running as Administrator.' -ForegroundColor Yellow
        $exitCode = 11
    }
    catch {
        Write-Host ''
        Write-Fail "Unexpected error: $($_.Exception.Message)"
        Write-Host "    At line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkGray
        $exitCode = 99
    }
    finally {
        Write-Host ''
        Write-SectionHeader 'Cleanup'
        Remove-TempDir -Path $tempDir
        Write-OK 'Temp files removed'
        Write-Host ''
        if ($exitCode -eq 0) {
            Write-Host "  Thank you for using $($script:CONFIG.ToolName)!" -ForegroundColor Cyan
        }
        Write-Host ''
    }

    exit $exitCode
}

Start-Launcher
