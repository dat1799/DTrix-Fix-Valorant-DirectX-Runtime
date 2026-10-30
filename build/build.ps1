#Requires -Version 5.1
<#
.SYNOPSIS
    DTrix DirectX Tool - Build Script
    Doc source, kiem tra cu phap, tinh SHA-256, ky so (neu co cert),
    sinh manifest.json, va chuan bi artifacts de upload len GitHub Releases.

.USAGE
    # Build thuong
    .\build.ps1

    # Build + ky so
    .\build.ps1 -Sign

    # Chi dinh phien ban
    .\build.ps1 -Version "1.2.0" -Force
#>
param(
    [string]$Version = "1.0.0",
    [switch]$Sign,
    [string]$CertThumbprint = "",
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─────────────────────────────────────────────
# PATHS
# ─────────────────────────────────────────────
$ROOT          = Split-Path -Parent $PSScriptRoot
$PAYLOAD_SRC   = Join-Path $ROOT "payload\check-directx.ps1"
$LAUNCHER_SRC  = Join-Path $ROOT "launcher\launcher.ps1"
$MANIFEST_SRC  = Join-Path $ROOT "manifest\manifest.json"
$DIST_DIR      = Join-Path $ROOT "build\dist"
$DIST_PAYLOAD  = Join-Path $DIST_DIR "check-directx.ps1"
$DIST_LAUNCHER = Join-Path $DIST_DIR "launcher.ps1"
$DIST_MANIFEST = Join-Path $DIST_DIR "manifest.json"

$GITHUB_REPO   = "dat1799/Check-Valorant-DirectX-Runtime"
$PAYLOAD_URL   = "https://github.com/$GITHUB_REPO/releases/download/v$Version/check-directx.ps1"

# ─────────────────────────────────────────────
# UI
# ─────────────────────────────────────────────
function Write-Header {
    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "   DTrix DirectX Tool - Build System " -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "  Version   : $Version"
    Write-Host "  Sign      : $Sign"
    Write-Host "  Timestamp : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
    Write-Host ""
}
function Write-Step { param([int]$n,[string]$msg) Write-Host "[$n] $msg" -ForegroundColor Cyan }
function Write-OK   { param([string]$m) Write-Host "    OK  $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "    !!  $m" -ForegroundColor Yellow }
function Write-Fail { param([string]$m) Write-Host "    ERR $m" -ForegroundColor Red }

# ─────────────────────────────────────────────
# STEP 1 - Validate source
# ─────────────────────────────────────────────
function Step1_ValidateSource {
    Write-Step 1 "Reading and validating source files"

    if (-not (Test-Path $PAYLOAD_SRC)) {
        Write-Fail "Payload not found: $PAYLOAD_SRC"
        throw "Payload source does not exist"
    }
    Write-OK "Payload : $PAYLOAD_SRC"

    if (-not (Test-Path $LAUNCHER_SRC)) {
        Write-Fail "Launcher not found: $LAUNCHER_SRC"
        throw "Launcher source does not exist"
    }
    Write-OK "Launcher: $LAUNCHER_SRC"

    Write-Host "    Checking payload syntax..." -ForegroundColor DarkGray
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile(
        $PAYLOAD_SRC, [ref]$null, [ref]$errors)
    if ($errors.Count -gt 0) {
        $errors | ForEach-Object { Write-Fail "Syntax: $($_.Message) (line $($_.Extent.StartLineNumber))" }
        throw "Payload has syntax errors"
    }
    Write-OK "Payload syntax valid"

    Write-Host "    Checking launcher syntax..." -ForegroundColor DarkGray
    $null = [System.Management.Automation.Language.Parser]::ParseFile(
        $LAUNCHER_SRC, [ref]$null, [ref]$errors)
    if ($errors.Count -gt 0) {
        $errors | ForEach-Object { Write-Fail "Syntax: $($_.Message) (line $($_.Extent.StartLineNumber))" }
        throw "Launcher has syntax errors"
    }
    Write-OK "Launcher syntax valid"
}

# ─────────────────────────────────────────────
# STEP 2 - Prepare dist
# ─────────────────────────────────────────────
function Step2_PrepareDist {
    Write-Step 2 "Preparing dist directory"

    if (Test-Path $DIST_DIR) {
        if ($Force) {
            Remove-Item -Path $DIST_DIR -Recurse -Force
            Write-OK "Removed old dist"
        } else {
            Write-Warn "Dist already exists. Use -Force to overwrite."
        }
    }
    New-Item -ItemType Directory -Path $DIST_DIR -Force | Out-Null
    Write-OK "Dist dir: $DIST_DIR"

    Copy-Item -Path $PAYLOAD_SRC  -Destination $DIST_PAYLOAD  -Force
    Write-OK "Copied payload  -> $DIST_PAYLOAD"

    Copy-Item -Path $LAUNCHER_SRC -Destination $DIST_LAUNCHER -Force
    Write-OK "Copied launcher -> $DIST_LAUNCHER"
}

# ─────────────────────────────────────────────
# STEP 3 - Compute SHA-256
# ─────────────────────────────────────────────
function Step3_ComputeHash {
    Write-Step 3 "Computing SHA-256 hash"
    $hash = (Get-FileHash -Path $DIST_PAYLOAD -Algorithm SHA256).Hash.ToUpper()
    Write-OK "SHA-256: $hash"
    return $hash
}

# ─────────────────────────────────────────────
# STEP 4 - Sign (optional)
# ─────────────────────────────────────────────
function Step4_SignPayload {
    Write-Step 4 "Authenticode signing"

    if (-not $Sign) {
        Write-Warn "Skipped (-Sign not passed). Payload will NOT have a digital signature."
        Write-Host "    -> Only SHA-256 will be used for verification." -ForegroundColor DarkGray
        return $null
    }

    $cert = $null
    if ($CertThumbprint) {
        $cert = Get-ChildItem Cert:\CurrentUser\My |
            Where-Object { $_.Thumbprint -eq $CertThumbprint }
        if (-not $cert) {
            $cert = Get-ChildItem Cert:\LocalMachine\My |
                Where-Object { $_.Thumbprint -eq $CertThumbprint }
        }
    }
    else {
        $cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object {
            $_.HasPrivateKey -and
            $_.NotAfter -gt (Get-Date) -and
            ($_.EnhancedKeyUsageList | Where-Object { $_.ObjectId -eq '1.3.6.1.5.5.7.3.3' })
        } | Sort-Object NotAfter -Descending | Select-Object -First 1
    }

    if (-not $cert) {
        Write-Warn "No valid Code Signing Certificate found."
        Write-Host "    -> To get one: DigiCert / Sectigo (~USD 100-500/year)" -ForegroundColor DarkGray
        Write-Host "    -> Build continues WITHOUT signature." -ForegroundColor Yellow
        return $null
    }

    Write-OK "Using cert: $($cert.Subject)"
    Write-OK "Expires   : $($cert.NotAfter)"

    $sigResult = Set-AuthenticodeSignature `
        -FilePath $DIST_PAYLOAD `
        -Certificate $cert `
        -TimestampServer "http://timestamp.digicert.com"

    if ($sigResult.Status -eq 'Valid') {
        Write-OK "Signing successful"
        $newHash = (Get-FileHash -Path $DIST_PAYLOAD -Algorithm SHA256).Hash.ToUpper()
        Write-OK "SHA-256 after signing: $newHash"
        $signer = $cert.Subject -replace '^CN=([^,]+).*', '$1'
        return @{ Signer = $signer; Hash = $newHash }
    }
    else {
        Write-Fail "Signing failed: $($sigResult.Status)"
        throw "Authenticode signing failed"
    }
}

# ─────────────────────────────────────────────
# STEP 5 - Generate manifest.json
# ─────────────────────────────────────────────
function Step5_GenerateManifest {
    param([string]$Hash, [hashtable]$SignInfo)
    Write-Step 5 "Generating manifest.json"

    $payloadSize = (Get-Item $DIST_PAYLOAD).Length
    $signerName  = if ($SignInfo) { $SignInfo.Signer } else { "" }
    $finalHash   = if ($SignInfo -and $SignInfo.Hash) { $SignInfo.Hash } else { $Hash }

    $manifest = [ordered]@{
        version            = $Version
        releaseDate        = (Get-Date -Format 'yyyy-MM-dd')
        changelog          = "Release v$Version"
        minLauncherVersion = "1.0.0"
        payloadUrl         = $PAYLOAD_URL
        sha256             = $finalHash
        payloadSizeBytes   = $payloadSize
        authenticode       = [ordered]@{
            required       = ($Sign -and ($null -ne $SignInfo))
            expectedSigner = $signerName
        }
        buildInfo          = [ordered]@{
            builtAt        = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
            builtBy        = $env:USERNAME
            psVersion      = $PSVersionTable.PSVersion.ToString()
        }
    }

    $json = $manifest | ConvertTo-Json -Depth 5
    $json | Set-Content -Path $DIST_MANIFEST -Encoding UTF8
    Write-OK "manifest.json -> $DIST_MANIFEST"

    $json | Set-Content -Path $MANIFEST_SRC -Encoding UTF8
    Write-OK "manifest.json updated -> $MANIFEST_SRC"

    return $manifest
}

# ─────────────────────────────────────────────
# STEP 6 - Verify artifact
# ─────────────────────────────────────────────
function Step6_VerifyArtifact {
    param([string]$ExpectedHash)
    Write-Step 6 "Verifying final artifact"

    foreach ($f in @($DIST_PAYLOAD, $DIST_LAUNCHER, $DIST_MANIFEST)) {
        if (Test-Path $f) {
            Write-OK "Exists: $(Split-Path $f -Leaf)"
        }
        else {
            Write-Fail "MISSING: $f"
            throw "Artifact missing"
        }
    }

    $actual = (Get-FileHash -Path $DIST_PAYLOAD -Algorithm SHA256).Hash.ToUpper()
    if ($actual -eq $ExpectedHash.ToUpper()) {
        Write-OK "Hash match: $actual"
    }
    else {
        Write-Fail "Hash MISMATCH!"
        Write-Host "    Expected: $ExpectedHash" -ForegroundColor Red
        Write-Host "    Actual  : $actual"       -ForegroundColor Red
        throw "Artifact verification failed"
    }

    $m = Get-Content $DIST_MANIFEST -Raw | ConvertFrom-Json
    if ($m.sha256 -eq $ExpectedHash) {
        Write-OK "manifest.json consistent"
    }
    else {
        Write-Fail "manifest.json SHA256 does not match artifact"
        throw "Manifest inconsistency"
    }
}

# ─────────────────────────────────────────────
# STEP 7 - Summary and next steps
# ─────────────────────────────────────────────
function Step7_Summary {
    param([hashtable]$Manifest)
    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host "       BUILD SUCCESSFUL              " -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Version    : v$Version"           -ForegroundColor White
    Write-Host "  SHA-256    : $($Manifest.sha256)" -ForegroundColor White
    Write-Host "  Artifacts  : $DIST_DIR"           -ForegroundColor White
    Write-Host ""
    Write-Host "--- Next Steps ---" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1. Commit and push manifest:" -ForegroundColor Yellow
    Write-Host "       git add manifest/manifest.json"
    Write-Host "       git commit -m 'Release v$Version'"
    Write-Host "       git push origin main"
    Write-Host ""
    Write-Host "  2. Create GitHub Release v${Version}:" -ForegroundColor Yellow
    Write-Host "       gh release create v$Version \"$DIST_PAYLOAD\" --title 'DirectX Tool v$Version'"
    Write-Host ""
    Write-Host "  3. Update Gist with launcher.ps1 (only if launcher changed):" -ForegroundColor Yellow
    Write-Host "       File: $DIST_LAUNCHER"
    Write-Host ""
    Write-Host "  4. Users run:" -ForegroundColor Yellow
    Write-Host "       irm 'https://gist.githubusercontent.com/dat1799/GIST_ID/raw/launcher.ps1' | iex"
    Write-Host ""
}

# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────
try {
    Write-Header
    Step1_ValidateSource
    Step2_PrepareDist
    $hash      = Step3_ComputeHash
    $signInfo  = Step4_SignPayload
    $finalHash = if ($signInfo -and $signInfo.Hash) { $signInfo.Hash } else { $hash }
    $manifest  = Step5_GenerateManifest -Hash $hash -SignInfo $signInfo
    Step6_VerifyArtifact -ExpectedHash $finalHash
    Step7_Summary -Manifest $manifest
    exit 0
}
catch {
    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Red
    Write-Host "         BUILD FAILED                " -ForegroundColor Red
    Write-Host "=====================================" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  At   : $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkGray
    exit 1
}
