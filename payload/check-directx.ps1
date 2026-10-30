# check-directx.ps1
# Kiem tra chu ky TAT CA file DLL trong System32 va SysWOW64,
# cung voi cac thanh phan Valorant / Unreal Engine can (DirectX cu, Visual C++).
#
# Cach chay (PowerShell quyen admin):
#   Chi kiem tra:
#     powershell -ExecutionPolicy Bypass -File .\check-directx.ps1
#   Kiem tra va tu sua (hoi truoc moi file):
#     powershell -ExecutionPolicy Bypass -File .\check-directx.ps1 -Fix -DxSetup "E:\DX\DXSETUP.exe"
#   Tu sua khong hoi:
#     powershell -ExecutionPolicy Bypass -File .\check-directx.ps1 -Fix -Force -DxSetup "E:\DX\DXSETUP.exe"
#
# Che do -Fix:
#   - File DirectX cu bi sua: doi ten thanh .bak roi cai lai bang DXSETUP (chay an).
#   - File Windows bi sua: KHONG doi ten (de tranh hong Windows), ma chay sfc + DISM.
#   - File khong co chu ky / file hang khac: chi bao cao, khong dong vao.
# Luu y: quet toan bo co the mat 5-15 phut tuy may.

param(
    [switch]$Fix,
    [switch]$Force,
    [string]$DxSetup
)

$ErrorActionPreference = 'SilentlyContinue'
$folders = @("$env:WINDIR\System32", "$env:WINDIR\SysWOW64")
$desktop = [Environment]::GetFolderPath('Desktop')

# File DirectX cu (do DXSETUP June 2010 cai) - an toan de doi ten va cai lai
$dxLegacyRegex = '^(d3dx9_\d+|d3dx10(_\d+)?|d3dx11_\d+|d3dcompiler_(3[3-9]|4[0-3])|xinput1_[123]|x3daudio1_\d+|xapofx1_\d+|xaudio2_[0-7]|xactengine\d_\d+)\.dll$'

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-SigInfo($path) {
    $sig    = Get-AuthenticodeSignature $path
    $signer = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject -replace '^CN=([^,]+).*','$1' } else { '-' }
    [PSCustomObject]@{ Status = [string]$sig.Status; Signer = $signer }
}

if ($Fix -and -not (Test-Admin)) {
    Write-Host "Che do -Fix can quyen admin. Hay mo PowerShell bang 'Run as administrator'." -ForegroundColor Red
    exit 1
}

# ================= 1. QUET =================
Write-Host "`n=== 1. Quet chu ky tat ca file DLL ===" -ForegroundColor Cyan
$files = foreach ($f in $folders) { Get-ChildItem -Path $f -Filter *.dll -File }
$total = $files.Count
Write-Host "  Tong so file: $total (vui long cho...)"

$i = 0
$results = foreach ($file in $files) {
    $i++
    if ($i % 100 -eq 0) {
        Write-Progress -Activity "Dang kiem tra chu ky DLL" -Status "$i / $total" -PercentComplete ($i / $total * 100)
    }
    $s = Get-SigInfo $file.FullName
    [PSCustomObject]@{
        File     = $file.FullName
        Name     = $file.Name
        SizeKB   = [math]::Round($file.Length / 1KB, 1)
        Modified = $file.LastWriteTime
        Status   = $s.Status
        Signer   = $s.Signer
    }
}
Write-Progress -Activity "Dang kiem tra chu ky DLL" -Completed

$tampered  = @($results | Where-Object { $_.Status -in 'HashMismatch','NotTrusted','UnknownError','Incompatible' })
$unsigned  = @($results | Where-Object { $_.Status -eq 'NotSigned' })
$thirdPart = @($results | Where-Object { $_.Status -eq 'Valid' -and $_.Signer -notlike 'Microsoft*' })

Write-Host "`n[NGUY HIEM] File bi sua hoac chu ky khong hop le: $($tampered.Count)" -ForegroundColor Red
if ($tampered) { $tampered | Sort-Object Modified -Descending | Format-Table File, SizeKB, Modified, Status, Signer -AutoSize }

Write-Host "[CAN XEM LAI] File khong co chu ky: $($unsigned.Count)" -ForegroundColor Yellow
if ($unsigned) { $unsigned | Sort-Object Modified -Descending | Format-Table File, SizeKB, Modified -AutoSize }

Write-Host "[THONG TIN] File ky boi hang khac Microsoft (thuong la driver, binh thuong): $($thirdPart.Count)" -ForegroundColor Gray
if ($thirdPart) {
    $thirdPart | Group-Object Signer | Sort-Object Count -Descending |
        Format-Table @{n='Hang ky';e={$_.Name}}, @{n='So file';e={$_.Count}} -AutoSize
}

# ================= 2. FILE VALORANT CAN =================
Write-Host "`n=== 2. File Valorant can (xinput1_3, X3DAudio1_7) ===" -ForegroundColor Cyan
foreach ($folder in $folders) {
    foreach ($name in @('xinput1_3.dll','X3DAudio1_7.dll')) {
        $path = Join-Path $folder $name
        $r = $results | Where-Object { $_.File -eq $path }
        if (-not $r) {
            Write-Host "  [THIEU] $path" -ForegroundColor Red
        } elseif ($r.Status -eq 'Valid' -and $r.Signer -like 'Microsoft*') {
            Write-Host "  [OK]    $path" -ForegroundColor Green
        } else {
            Write-Host "  [LOI]   $path ($($r.Status))" -ForegroundColor Red
        }
    }
}

# ================= 3. VC++ =================
Write-Host "`n=== 3. Visual C++ 2015-2022 Redistributable ===" -ForegroundColor Cyan
$vcKeys = [ordered]@{
    'x64' = 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64'
    'x86' = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x86'
}
foreach ($arch in $vcKeys.Keys) {
    $vc = Get-ItemProperty $vcKeys[$arch]
    if ($vc -and $vc.Installed -eq 1) {
        Write-Host "  [OK]    VC++ $arch - phien ban $($vc.Version)" -ForegroundColor Green
    } else {
        Write-Host "  [THIEU] VC++ $arch" -ForegroundColor Red
    }
}

# ================= 4. HE THONG =================
Write-Host "`n=== 4. Thong tin he thong ===" -ForegroundColor Cyan
$os = Get-CimInstance Win32_OperatingSystem
Write-Host "  Windows : $($os.Caption) (build $($os.BuildNumber))"
Get-CimInstance Win32_VideoController | ForEach-Object {
    Write-Host "  GPU     : $($_.Name) - driver $($_.DriverVersion)"
}

$csvAll = Join-Path $desktop "dll-check-all-$env:COMPUTERNAME.csv"
$csvBad = Join-Path $desktop "dll-check-problems-$env:COMPUTERNAME.csv"
$results | Export-Csv -Path $csvAll -NoTypeInformation -Encoding UTF8
($tampered + $unsigned) | Export-Csv -Path $csvBad -NoTypeInformation -Encoding UTF8
Write-Host "`nDa luu:" -ForegroundColor Yellow
Write-Host "  Toan bo  : $csvAll"
Write-Host "  File loi : $csvBad"

# ================= 5. SUA =================
$dxBad = @($tampered | Where-Object { $_.Name -match $dxLegacyRegex })
$osBad = @($tampered | Where-Object { $_.Name -notmatch $dxLegacyRegex })

if (-not $Fix) {
    if ($tampered) {
        Write-Host "`nCo $($tampered.Count) file bi sua. Chay lai voi -Fix de script tu sua, vi du:" -ForegroundColor Yellow
        Write-Host "  powershell -ExecutionPolicy Bypass -File .\check-directx.ps1 -Fix -DxSetup `"E:\DX\DXSETUP.exe`""
    }
    Write-Host ""
    exit 0
}

if (-not $tampered) {
    Write-Host "`nKhong co file nao can sua." -ForegroundColor Green
    Write-Host ""
    exit 0
}

Write-Host "`n=== 5. Sua file bi sua ===" -ForegroundColor Cyan
Write-Host "  Khuyen nghi: quet virus (Defender Offline scan) truoc khi sua." -ForegroundColor Yellow

$renamed = @()
foreach ($item in $dxBad) {
    if (-not $Force) {
        $ans = Read-Host "  Doi ten $($item.File) ($($item.Status))? (y/n)"
        if ($ans -notmatch '^[yY]') { Write-Host "    Bo qua." -ForegroundColor Gray; continue }
    }
    $bak = "$($item.File).bak"
    if (Test-Path $bak) { $bak = "$($item.File).$(Get-Date -Format 'yyyyMMdd-HHmmss').bak" }
    $newName = Split-Path $bak -Leaf

    Rename-Item -LiteralPath $item.File -NewName $newName -ErrorAction SilentlyContinue
    if (Test-Path $item.File) {
        # Lay quyen so huu roi thu lai (S-1-5-32-544 = nhom Administrators, khong phu thuoc ngon ngu Windows)
        takeown /f "$($item.File)" /a | Out-Null
        icacls "$($item.File)" /grant "*S-1-5-32-544:F" | Out-Null
        Rename-Item -LiteralPath $item.File -NewName $newName -ErrorAction SilentlyContinue
    }

    if (Test-Path $item.File) {
        Write-Host "    [THAT BAI] Khong doi ten duoc $($item.File)" -ForegroundColor Red
    } else {
        Write-Host "    [OK] -> $bak" -ForegroundColor Green
        $renamed += [PSCustomObject]@{ Original = $item.File; Backup = $bak; Status = $item.Status; Time = Get-Date }
    }
}

if ($renamed) {
    $logPath = Join-Path $desktop "dll-renamed-$env:COMPUTERNAME.csv"
    $renamed | Export-Csv -Path $logPath -NoTypeInformation -Encoding UTF8 -Append
    Write-Host "  Da ghi danh sach file doi ten vao: $logPath"

    if ($DxSetup -and (Test-Path $DxSetup)) {
        Write-Host "  Dang cai lai DirectX tu $DxSetup ..." -ForegroundColor Cyan
        Start-Process -FilePath $DxSetup -ArgumentList '/silent' -Wait
    } else {
        Write-Host "  Chua co duong dan DXSETUP.exe (tham so -DxSetup)." -ForegroundColor Yellow
        Write-Host "  Hay tu chay DXSETUP.exe bang quyen admin roi bam Enter de kiem tra lai." -ForegroundColor Yellow
        Read-Host "  Bam Enter khi cai xong"
    }

    Write-Host "`n  Kiem tra lai file vua cai:" -ForegroundColor Cyan
    foreach ($r in $renamed) {
        if (-not (Test-Path $r.Original)) {
            Write-Host "    [THIEU] $($r.Original) - DXSETUP chua cai lai file nay" -ForegroundColor Red
            continue
        }
        $s = Get-SigInfo $r.Original
        if ($s.Status -eq 'Valid' -and $s.Signer -like 'Microsoft*') {
            Write-Host "    [OK]  $($r.Original)" -ForegroundColor Green
        } else {
            Write-Host "    [LOI] $($r.Original) ($($s.Status))" -ForegroundColor Red
        }
    }
}

if ($osBad) {
    Write-Host "`n  Co $($osBad.Count) file Windows bi sua (khong doi ten de tranh hong he thong):" -ForegroundColor Yellow
    $osBad | ForEach-Object { Write-Host "    $($_.File)" }
    $run = $true
    if (-not $Force) { $run = (Read-Host "  Chay sfc /scannow va DISM de khoi phuc? Mat 10-30 phut. (y/n)") -match '^[yY]' }
    if ($run) {
        DISM /Online /Cleanup-Image /RestoreHealth
        sfc /scannow
        Write-Host "  Xong. Khoi dong lai may roi chay lai script nay de kiem tra." -ForegroundColor Green
    }
}

Write-Host "`n=== KHOI PHUC (neu can) ===" -ForegroundColor Gray
Write-Host "  Neu sau khi sua co phan mem bi loi, doi ten file .bak ve ten cu"
Write-Host "  (danh sach nam trong file dll-renamed-*.csv tren Desktop)."
Write-Host ""
