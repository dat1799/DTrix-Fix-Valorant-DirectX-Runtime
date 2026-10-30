#Requires -Version 5.1
<#
.SYNOPSIS
    DTrix DirectX Tool - Payload Verification Script
    Independently verifies a payload artifact: hash, structure, Authenticode.

.USAGE
    # Verify payload with manifest
    .\verify.ps1 -PayloadPath ".\dist\check-directx.ps1" -ManifestPath ".\dist\manifest.json"

    # Verify payload with explicit hash
    .\verify.ps1 -PayloadPath ".\dist\check-directx.ps1" -ExpectedHash "ABC123..."

    # Verify payload with remote manifest URL
    .\verify.ps1 -PayloadPath ".\dist\check-directx.ps1" -ManifestUrl "https://raw.githubusercontent.com/..."

    # Strict mode: require valid Authenticode
    .\verify.ps1 -PayloadPath ".\dist\check-directx.ps1" -ManifestPath ".\dist\manifest.json" -Strict
#>
param(
    [Parameter(Mandatory)][string]$PayloadPath,
    [string]$ManifestPath  = "",
    [string]$ManifestUrl   = "",
    [string]$ExpectedHash  = "",
    [switch]$Strict
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─────────────────────────────────────────────
# TEST TRACKING
# ─────────────────────────────────────────────
$TESTS  = [System.Collections.Generic.List[hashtable]]::new()
$PASSED = 0
$FAILED = 0

function Add-Result {
    param([string]$Name, [bool]$Ok, [string]$Detail = "")
    $script:TESTS.Add(@{ Name = $Name; Passed = $Ok; Detail = $Detail })
    if ($Ok) { $script:PASSED++ } else { $script:FAILED++ }
}

function Write-Result {
    param([hashtable]$t)
    $symbol = if ($t.Passed) { "PASS" } else { "FAIL" }
    $color  = if ($t.Passed) { 'Green' } else { 'Red' }
    Write-Host "  [$symbol] $($t.Name)" -ForegroundColor $color
    if ($t.Detail) { Write-Host "         $($t.Detail)" -ForegroundColor DarkGray }
}

# ─────────────────────────────────────────────
# HEADER
# ─────────────────────────────────────────────
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   DTrix Payload Verification Tool        " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# ─────────────────────────────────────────────
# TEST 1 - File exists
# ─────────────────────────────────────────────
Write-Host "[1/6] File existence check" -ForegroundColor Cyan
$fileExists = Test-Path $PayloadPath
Add-Result "Payload file exists" $fileExists $PayloadPath

if (-not $fileExists) {
    Write-Host "  STOP: File does not exist. Cannot continue." -ForegroundColor Red
    Write-Result $TESTS[0]
    exit 1
}

$fi = Get-Item $PayloadPath
Add-Result "File is not empty" ($fi.Length -gt 0) "Size: $([math]::Round($fi.Length/1KB,1)) KB"

# ─────────────────────────────────────────────
# TEST 2 - PowerShell syntax
# ─────────────────────────────────────────────
Write-Host "[2/6] PowerShell syntax check" -ForegroundColor Cyan
try {
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile(
        $PayloadPath, [ref]$null, [ref]$parseErrors)
    $syntaxOK = ($parseErrors.Count -eq 0)
    $detail   = if ($syntaxOK) { "No errors" } else { "$($parseErrors.Count) error(s)" }
    Add-Result "PowerShell syntax valid" $syntaxOK $detail
    if (-not $syntaxOK) {
        $parseErrors | ForEach-Object {
            Write-Host "    -> $($_.Message) (line $($_.Extent.StartLineNumber))" -ForegroundColor Red
        }
    }
}
catch {
    Add-Result "PowerShell syntax valid" $false $_.Exception.Message
}

# ─────────────────────────────────────────────
# TEST 3 - SHA-256 hash
# ─────────────────────────────────────────────
Write-Host "[3/6] SHA-256 verification" -ForegroundColor Cyan
$actualHash = (Get-FileHash -Path $PayloadPath -Algorithm SHA256).Hash.ToUpper()
Write-Host "  Computed hash : $actualHash" -ForegroundColor DarkGray

$targetHash = ""

if ($ExpectedHash) {
    $targetHash = $ExpectedHash.ToUpper().Trim()
    Write-Host "  Expected (arg): $targetHash" -ForegroundColor DarkGray
}

if (-not $targetHash -and $ManifestPath -and (Test-Path $ManifestPath)) {
    try {
        $mObj = Get-Content $ManifestPath -Raw | ConvertFrom-Json
        $targetHash = $mObj.sha256.ToUpper().Trim()
        Write-Host "  Expected (manifest): $targetHash" -ForegroundColor DarkGray
    }
    catch {
        Add-Result "Read manifest file" $false $_.Exception.Message
    }
}

if (-not $targetHash -and $ManifestUrl) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $mRaw = Invoke-WebRequest -Uri $ManifestUrl -UseBasicParsing |
            Select-Object -ExpandProperty Content
        $mObj = $mRaw | ConvertFrom-Json
        $targetHash = $mObj.sha256.ToUpper().Trim()
        Write-Host "  Expected (URL): $targetHash" -ForegroundColor DarkGray
    }
    catch {
        Add-Result "Fetch manifest from URL" $false $_.Exception.Message
    }
}

if ($targetHash) {
    $hashMatch = ($actualHash -eq $targetHash)
    Add-Result "SHA-256 matches manifest" $hashMatch "Expected: $targetHash"
}
else {
    Add-Result "SHA-256 (no target provided)" $true "Hash: $actualHash - nothing to compare against"
    Write-Host "  NOTE: Provide -ManifestPath, -ManifestUrl, or -ExpectedHash for full verification." -ForegroundColor Yellow
}

# ─────────────────────────────────────────────
# TEST 4 - Authenticode
# ─────────────────────────────────────────────
Write-Host "[4/6] Authenticode check" -ForegroundColor Cyan
try {
    $sig       = Get-AuthenticodeSignature -FilePath $PayloadPath -ErrorAction Stop
    $sigStatus = [string]$sig.Status

    switch ($sigStatus) {
        'Valid' {
            $cn  = $sig.SignerCertificate.Subject -replace '^CN=([^,]+).*','$1'
            $exp = $sig.SignerCertificate.NotAfter
            Add-Result "Authenticode: Valid" $true "Signer: $cn | Expires: $exp"
        }
        'NotSigned' {
            $pass = -not $Strict
            $msg  = if ($Strict) { "FAIL: -Strict requires signature" } else { "Not signed (OK without -Strict)" }
            Add-Result "Authenticode: NotSigned" $pass $msg
        }
        'HashMismatch' {
            Add-Result "Authenticode: HashMismatch" $false "File was modified after signing!"
        }
        'NotTrusted' {
            Add-Result "Authenticode: NotTrusted" $false "Certificate is not trusted"
        }
        default {
            Add-Result "Authenticode: $sigStatus" $false $sig.StatusMessage
        }
    }
}
catch {
    Add-Result "Authenticode (read error)" $false $_.Exception.Message
}

# ─────────────────────────────────────────────
# TEST 5 - Required content checks
# ─────────────────────────────────────────────
Write-Host "[5/6] Content integrity checks" -ForegroundColor Cyan
$content = Get-Content -Path $PayloadPath -Raw -Encoding UTF8

# Required functionality
$required = @(
    @{ Pattern = 'Test-Admin';                     Name = "Function: Test-Admin exists" }
    @{ Pattern = 'Get-AuthenticodeSignature';       Name = "DLL signature scanning" }
    @{ Pattern = 'System32';                        Name = "Scans System32" }
    @{ Pattern = 'SysWOW64';                        Name = "Scans SysWOW64" }
    @{ Pattern = 'Export-Csv';                      Name = "CSV report export" }
    @{ Pattern = 'Win32_VideoController';           Name = "GPU/Driver check" }
    @{ Pattern = 'VisualStudio.*VC.*Runtimes';      Name = "VC++ Runtime check" }
    @{ Pattern = 'DISM|sfc /scannow';               Name = "Windows repair commands (DISM/SFC)" }
    @{ Pattern = 'xinput1_3|X3DAudio1_7';           Name = "Valorant DLL check" }
    @{ Pattern = '\[switch\]\$Fix';                 Name = "Parameter: -Fix switch" }
)
foreach ($c in $required) {
    Add-Result $c.Name ($content -match $c.Pattern)
}

# Dangerous patterns that must NOT be present
$forbidden = @(
    @{ Pattern = 'Set-MpPreference.*DisableRealtimeMonitoring.*\$true'
       Name    = "Does NOT disable Defender" }
    @{ Pattern = 'Start-Process.*-WindowStyle\s+Hidden'
       Name    = "Does NOT launch hidden processes" }
    @{ Pattern = 'New-Object\s+Net\.WebClient.*DownloadString.*Invoke-Expression'
       Name    = "Does NOT download+exec arbitrary code" }
)
foreach ($d in $forbidden) {
    $found = $content -match $d.Pattern
    Add-Result $d.Name (-not $found) $(if ($found) { "WARNING: suspicious pattern found!" } else { "Clean" })
}

# ─────────────────────────────────────────────
# TEST 6 - Manifest consistency
# ─────────────────────────────────────────────
Write-Host "[6/6] Manifest consistency" -ForegroundColor Cyan
if ($ManifestPath -and (Test-Path $ManifestPath)) {
    try {
        $mData = Get-Content $ManifestPath -Raw | ConvertFrom-Json
        Add-Result "Manifest parses OK"          $true
        Add-Result "Manifest has 'version'"      ($null -ne $mData.version)     "v$($mData.version)"
        Add-Result "Manifest has 'sha256'"       ($null -ne $mData.sha256)      $mData.sha256
        Add-Result "Manifest has 'payloadUrl'"   ($null -ne $mData.payloadUrl)  $mData.payloadUrl
        Add-Result "payloadUrl uses HTTPS"       ($mData.payloadUrl -match '^https://')
        Add-Result "sha256 is 64-char hex"       ($mData.sha256 -match '^[0-9A-Fa-f]{64}$')
    }
    catch {
        Add-Result "Manifest parses OK" $false $_.Exception.Message
    }
}
else {
    Write-Host "  (Skipped - no -ManifestPath provided)" -ForegroundColor DarkGray
}

# ─────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " VERIFICATION RESULTS" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
$TESTS | ForEach-Object { Write-Result $_ }
Write-Host ""

$totalTests = $PASSED + $FAILED
$color = if ($FAILED -eq 0) { 'Green' } else { 'Red' }
Write-Host "  Total: $totalTests  |  Passed: $PASSED  |  Failed: $FAILED" -ForegroundColor $color
Write-Host ""

if ($FAILED -eq 0) {
    Write-Host "  [PASS] ALL CHECKS PASSED - Payload is ready for release." -ForegroundColor Green
    exit 0
}
else {
    Write-Host "  [FAIL] $FAILED CHECK(S) FAILED - Review before releasing." -ForegroundColor Red
    exit 1
}
