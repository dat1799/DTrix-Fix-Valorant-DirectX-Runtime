# check-directx.ps1 - Fix Valorant DirectX Runtime
#
# Cach chay: mo PowerShell (Start > go powershell > Run as administrator), dan lenh:
#   irm "https://gist.githubusercontent.com/dat1799/150903857de1134ffc2b4e8ba6c75e2e/raw/check-directx.ps1?$(Get-Random)" | iex
# Sau do chon chuc nang trong menu bang cach go so roi bam Enter.
#
# Script tu tai DirectX June 2010 va Visual C++ tu trang Microsoft khi can.
# File tai ve tam nam o C:\ValorantDxFix va duoc xoa khi thoat bang phim 0.

& {
$ScriptUrl = 'https://gist.githubusercontent.com/dat1799/150903857de1134ffc2b4e8ba6c75e2e/raw/check-directx.ps1'
$DxUrl     = 'https://download.microsoft.com/download/8/4/A/84A35BF1-DAFE-4AE8-82AF-AD2AE20B6B14/directx_Jun2010_redist.exe'
$VcUrls    = [ordered]@{
    'x64' = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'
    'x86' = 'https://aka.ms/vs/17/release/vc_redist.x86.exe'
}
$VcKeys    = [ordered]@{
    'x64' = 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64'
    'x86' = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x86'
}
$Folders   = @("$env:WINDIR\System32", "$env:WINDIR\SysWOW64")
$WorkDir   = "$env:SystemDrive\ValorantDxFix"
$ValorantFiles = @('xinput1_3.dll', 'X3DAudio1_7.dll')

# File DirectX cu do DXSETUP June 2010 cai - an toan de doi ten va cai lai
$DxPatterns    = @('d3dx9_*.dll','d3dx10*.dll','d3dx11_*.dll','D3DCompiler_*.dll','xinput1_*.dll',
                   'X3DAudio*.dll','XAPOFX*.dll','XAudio2_*.dll','xactengine*.dll')
$DxLegacyRegex = '^(d3dx9_\d+|d3dx10(_\d+)?|d3dx11_\d+|d3dcompiler_(3[3-9]|4[0-3])|xinput1_[123]|x3daudio1_\d+|xapofx1_\d+|xaudio2_[0-7]|xactengine\d_\d+)\.dll$'

# Trang thai dung chung giua cac chuc nang
$State = @{ Problems = @() }

try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

# ======================= HAM CHUNG =======================

function Write-Title($text) {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "  $text" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
}

function Wait-Menu { Write-Host ""; Read-Host "Bam Enter de quay lai menu" | Out-Null }

function Confirm-Action($question) {
    $a = Read-Host "$question (y/n)"
    return ($a -match '^\s*[yY]')
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-FileFromWeb($url, $out) {
    $old = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'   # tat thanh tien trinh de tai nhanh hon
    try {
        Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -ErrorAction Stop
        return $true
    } catch {
        Write-Host "  Tai that bai: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    } finally {
        $ProgressPreference = $old
    }
}

function Grant-Access($path) {
    takeown /f "$path" /a 2>&1 | Out-Null
    icacls "$path" /grant "*S-1-5-32-544:F" 2>&1 | Out-Null   # S-1-5-32-544 = nhom Administrators
}

function Test-FileSignature($fileInfo) {
    $sig    = Get-AuthenticodeSignature $fileInfo.FullName -ErrorAction SilentlyContinue
    $signer = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject -replace '^CN=([^,]+).*','$1' } else { '-' }
    $status = [string]$sig.Status
    [PSCustomObject]@{
        File     = $fileInfo.FullName
        Name     = $fileInfo.Name
        SizeKB   = [math]::Round($fileInfo.Length / 1KB, 1)
        Modified = $fileInfo.LastWriteTime
        Status   = $status
        Signer   = $signer
        OK       = ($status -eq 'Valid' -and $signer -like 'Microsoft*')
    }
}

function Test-FileList($files, $activity) {
    $total = @($files).Count
    $i = 0
    $res = foreach ($f in $files) {
        $i++
        if ($i % 50 -eq 0 -or $i -eq $total) {
            Write-Progress -Activity $activity -Status "$i / $total" -PercentComplete ($i / [math]::Max($total,1) * 100)
        }
        Test-FileSignature $f
    }
    Write-Progress -Activity $activity -Completed
    return @($res)
}

function Get-DxFiles {
    $list = foreach ($folder in $Folders) {
        foreach ($p in $DxPatterns + @('msvcp140*.dll','vcruntime140*.dll')) {
            Get-ChildItem -Path $folder -Filter $p -File -ErrorAction SilentlyContinue
        }
    }
    return @($list | Sort-Object FullName -Unique)
}

function Get-MissingValorantFiles {
    $missing = foreach ($folder in $Folders) {
        foreach ($name in $ValorantFiles) {
            $p = Join-Path $folder $name
            if (-not (Test-Path $p)) { $p }
        }
    }
    return @($missing)
}

function Get-VcStatus {
    $r = [ordered]@{}
    foreach ($arch in $VcKeys.Keys) {
        $vc = Get-ItemProperty $VcKeys[$arch] -ErrorAction SilentlyContinue
        $r[$arch] = if ($vc -and $vc.Installed -eq 1) { [string]$vc.Version } else { $null }
    }
    return $r
}

function Show-ValorantAndVc {
    Write-Host "`n  File Valorant can:" -ForegroundColor Cyan
    foreach ($folder in $Folders) {
        foreach ($name in $ValorantFiles) {
            $p = Join-Path $folder $name
            if (-not (Test-Path $p)) {
                Write-Host "    [THIEU] $p" -ForegroundColor Red
            } else {
                $r = Test-FileSignature (Get-Item $p)
                if ($r.OK) { Write-Host "    [OK]    $p" -ForegroundColor Green }
                else       { Write-Host "    [LOI]   $p ($($r.Status))" -ForegroundColor Red }
            }
        }
    }
    Write-Host "`n  Visual C++ 2015-2022:" -ForegroundColor Cyan
    $vc = Get-VcStatus
    foreach ($arch in $vc.Keys) {
        if ($vc[$arch]) { Write-Host "    [OK]    $arch - phien ban $($vc[$arch])" -ForegroundColor Green }
        else            { Write-Host "    [THIEU] $arch" -ForegroundColor Red }
    }
}

function Show-BadTable($items, $title, $color) {
    Write-Host "`n  $title : $(@($items).Count)" -ForegroundColor $color
    if ($items) {
        $items | Sort-Object Modified -Descending |
            Format-Table @{n='File';e={$_.File}}, @{n='KB';e={$_.SizeKB}}, @{n='Ngay sua';e={$_.Modified}}, @{n='Trang thai';e={$_.Status}} -AutoSize |
            Out-Host
    }
}

# ======================= CHUC NANG =======================

function Invoke-QuickCheck {
    Write-Title "KIEM TRA NHANH (file DirectX va Visual C++)"
    $results = Test-FileList (Get-DxFiles) "Dang kiem tra file DirectX"
    $bad = @($results | Where-Object { -not $_.OK })
    $State.Problems = $bad
    if ($bad) {
        Show-BadTable $bad "[LOI] File bi sua hoac khong phai cua Microsoft" Red
        Write-Host "  => Chon chuc nang 4 (hoac 1) de sua." -ForegroundColor Yellow
    } else {
        Write-Host "`n  Tat ca $($results.Count) file DirectX / VC++ deu hop le." -ForegroundColor Green
    }
    Show-ValorantAndVc
}

function Invoke-FullCheck {
    Write-Title "KIEM TRA TOAN BO FILE DLL (5-15 phut)"
    $files = foreach ($f in $Folders) { Get-ChildItem -Path $f -Filter *.dll -File -ErrorAction SilentlyContinue }
    Write-Host "  Tong so file: $(@($files).Count). Vui long cho..."
    $results = Test-FileList $files "Dang kiem tra chu ky DLL"

    $tampered  = @($results | Where-Object { $_.Status -in 'HashMismatch','NotTrusted','UnknownError','Incompatible' })
    $unsigned  = @($results | Where-Object { $_.Status -eq 'NotSigned' })
    $thirdPart = @($results | Where-Object { $_.Status -eq 'Valid' -and $_.Signer -notlike 'Microsoft*' })
    $State.Problems = $tampered

    Show-BadTable $tampered "[NGUY HIEM] File bi sua / chu ky khong hop le" Red
    Show-BadTable $unsigned "[CAN XEM LAI] File khong co chu ky (thuong la phan mem cu, chua chac doc hai)" Yellow
    Write-Host "`n  [THONG TIN] File ky boi hang khac (driver...), binh thuong: $($thirdPart.Count)" -ForegroundColor Gray
    if ($thirdPart) {
        $thirdPart | Group-Object Signer | Sort-Object Count -Descending |
            Format-Table @{n='Hang ky';e={$_.Name}}, @{n='So file';e={$_.Count}} -AutoSize | Out-Host
    }
    Show-ValorantAndVc

    if ($tampered) {
        $dx = @($tampered | Where-Object { $_.Name -match $DxLegacyRegex })
        $os = @($tampered | Where-Object { $_.Name -notmatch $DxLegacyRegex })
        if ($dx) { Write-Host "`n  => $($dx.Count) file DirectX bi sua: chon chuc nang 4 de sua." -ForegroundColor Yellow }
        if ($os) { Write-Host "  => $($os.Count) file Windows bi sua: chon chuc nang 9 (sfc + DISM)." -ForegroundColor Yellow }
        Write-Host "  => Nen quet virus (chuc nang 6) va tim nguon goc (chuc nang 7)." -ForegroundColor Yellow
    }
}

function Get-DxSetup {
    $dir   = Join-Path $WorkDir 'DX'
    $setup = Join-Path $dir 'DXSETUP.exe'
    if (Test-Path $setup) { return $setup }

    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $exe = Join-Path $WorkDir 'directx_Jun2010_redist.exe'
    if (-not (Test-Path $exe)) {
        Write-Host "  Dang tai DirectX June 2010 tu Microsoft (~95 MB)..." -ForegroundColor Cyan
        if (-not (Get-FileFromWeb $DxUrl $exe)) { $exe = $null }
    }
    if ($exe) {
        Write-Host "  Dang giai nen..." -ForegroundColor Cyan
        Start-Process -FilePath $exe -ArgumentList '/Q', "/T:$dir" -Wait
    }
    if (Test-Path $setup) { return $setup }

    Write-Host "  Khong tu tai / giai nen duoc DirectX." -ForegroundColor Red
    $manual = Read-Host "  Neu da co DXSETUP.exe, nhap duong dan (vd E:\DX\DXSETUP.exe), de trong de huy"
    if ($manual) {
        $manual = $manual.Trim().Trim('"')
        if (Test-Path $manual) { return $manual }
        Write-Host "  Khong tim thay $manual" -ForegroundColor Red
    }
    return $null
}

function Rename-ToBak($path) {
    $bak = "$path.bak"
    if (Test-Path $bak) { $bak = "$path.$(Get-Date -Format 'yyyyMMdd-HHmmss').bak" }
    $leaf = Split-Path $bak -Leaf
    Rename-Item -LiteralPath $path -NewName $leaf -ErrorAction SilentlyContinue
    if (Test-Path $path) {
        Grant-Access $path
        Rename-Item -LiteralPath $path -NewName $leaf -ErrorAction SilentlyContinue
    }
    if (Test-Path $path) { return $null }
    return $bak
}

function Invoke-DxFix([switch]$NoConfirm) {
    Write-Title "SUA FILE DIRECTX BI LOI"
    $results = Test-FileList (Get-DxFiles) "Dang kiem tra file DirectX"
    $bad     = @($results | Where-Object { -not $_.OK -and $_.Name -match $DxLegacyRegex })
    $missing = Get-MissingValorantFiles
    if ($bad) { $State.Problems = @($results | Where-Object { -not $_.OK }) }

    if (-not $bad -and -not $missing) {
        Write-Host "`n  Khong co file DirectX nao bi loi hoac bi thieu." -ForegroundColor Green
        return $true
    }
    if ($bad)     { Show-BadTable $bad "File DirectX bi loi se duoc doi ten thanh .bak" Red }
    if ($missing) {
        Write-Host "`n  File Valorant can dang bi thieu:" -ForegroundColor Red
        $missing | ForEach-Object { Write-Host "    $_" }
    }
    if (-not $NoConfirm -and -not (Confirm-Action "`n  Tien hanh sua")) { return $false }

    $renamed = @()
    foreach ($b in $bad) {
        $bak = Rename-ToBak $b.File
        if ($bak) {
            Write-Host "  [OK]       $($b.File) -> .bak" -ForegroundColor Green
            $renamed += [PSCustomObject]@{ Original = $b.File; Backup = $bak }
        } else {
            Write-Host "  [THAT BAI] Khong doi ten duoc $($b.File)" -ForegroundColor Red
        }
    }

    $setup = Get-DxSetup
    if (-not $setup) {
        Write-Host "  Chua cai lai duoc DirectX. Cac file da doi ten van con o dang .bak (khoi phuc o chuc nang 8)." -ForegroundColor Red
        return $false
    }
    Write-Host "  Dang cai lai DirectX (chay an, 1-2 phut)..." -ForegroundColor Cyan
    Start-Process -FilePath $setup -ArgumentList '/silent' -Wait

    Write-Host "`n  Kiem tra lai:" -ForegroundColor Cyan
    $allOk = $true
    $toCheck = @($renamed | ForEach-Object { $_.Original }) +
               @(foreach ($folder in $Folders) { foreach ($n in $ValorantFiles) { Join-Path $folder $n } })
    foreach ($p in ($toCheck | Sort-Object -Unique)) {
        if (-not (Test-Path $p)) {
            Write-Host "    [THIEU] $p" -ForegroundColor Red; $allOk = $false; continue
        }
        $r = Test-FileSignature (Get-Item $p)
        if ($r.OK) { Write-Host "    [OK]    $p" -ForegroundColor Green }
        else       { Write-Host "    [LOI]   $p ($($r.Status))" -ForegroundColor Red; $allOk = $false }
    }
    if ($renamed) {
        Write-Host "`n  Da doi ten $($renamed.Count) file. Game chay duoc thi xoa file .bak o chuc nang 8." -ForegroundColor Gray
    }
    if (-not $allOk) {
        Write-Host "  Van con loi: co the co phan mem dang ghi de lai file. Hay quet virus (chuc nang 6)." -ForegroundColor Yellow
    }
    return $allOk
}

function Invoke-VcInstall {
    Write-Title "CAI / SUA VISUAL C++ 2015-2022"
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    foreach ($arch in $VcUrls.Keys) {
        $exe = Join-Path $WorkDir "vc_redist.$arch.exe"
        Write-Host "  Dang tai Visual C++ $arch..." -ForegroundColor Cyan
        if (-not (Test-Path $exe) -and -not (Get-FileFromWeb $VcUrls[$arch] $exe)) { continue }
        Write-Host "  Dang cai Visual C++ $arch..." -ForegroundColor Cyan
        $p = Start-Process -FilePath $exe -ArgumentList '/install','/quiet','/norestart' -Wait -PassThru
        if ($p.ExitCode -eq 1638) {
            $p = Start-Process -FilePath $exe -ArgumentList '/repair','/quiet','/norestart' -Wait -PassThru
        }
        switch ($p.ExitCode) {
            0       { Write-Host "    [OK] Visual C++ $arch" -ForegroundColor Green }
            3010    { Write-Host "    [OK] Visual C++ $arch (can khoi dong lai may)" -ForegroundColor Green }
            1638    { Write-Host "    [OK] Visual C++ $arch da co ban moi hon" -ForegroundColor Green }
            default { Write-Host "    [LOI] Visual C++ $arch - ma loi $($p.ExitCode)" -ForegroundColor Red }
        }
    }
}

function Invoke-VirusScan {
    Write-Title "QUET VIRUS BANG WINDOWS DEFENDER"
    if (-not (Get-Command Start-MpScan -ErrorAction SilentlyContinue)) {
        Write-Host "  Khong dung duoc Windows Defender tren may nay. Hay quet bang phan mem diet virus dang dung." -ForegroundColor Yellow
        return
    }
    Write-Host "  1. Quet nhanh (vai phut)"
    Write-Host "  2. Quet offline (KHUYEN DUNG, may se KHOI DONG LAI va quet ~15 phut)"
    Write-Host "  0. Quay lai"
    switch ((Read-Host "  Chon").Trim()) {
        '1' {
            Write-Host "  Dang quet nhanh..." -ForegroundColor Cyan
            try {
                Start-MpScan -ScanType QuickScan -ErrorAction Stop
                $threats = @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Sort-Object InitialDetectionTime -Descending | Select-Object -First 10)
                if ($threats) {
                    Write-Host "  Phat hien moi de doa (10 muc gan nhat):" -ForegroundColor Red
                    $threats | Format-Table InitialDetectionTime, @{n='File';e={$_.Resources -join ', '}} -AutoSize -Wrap | Out-Host
                } else {
                    Write-Host "  Khong phat hien moi de doa." -ForegroundColor Green
                }
            } catch {
                Write-Host "  Khong quet duoc: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "  (Thuong do may dang dung phan mem diet virus khac thay Defender.)" -ForegroundColor Yellow
            }
        }
        '2' {
            Write-Host "  Hay luu het cong viec dang lam truoc khi tiep tuc." -ForegroundColor Yellow
            if (Confirm-Action "  Khoi dong lai may de quet offline ngay bay gio") {
                try { Start-MpWDOScan -ErrorAction Stop }
                catch { Write-Host "  Khong chay duoc: $($_.Exception.Message)" -ForegroundColor Red }
            }
        }
    }
}

function Invoke-FindSource {
    Write-Title "TIM PHAN MEM NGHI DA GHI DE FILE"
    $dates = @($State.Problems | ForEach-Object { $_.Modified.Date } | Sort-Object -Unique)
    if ($dates) {
        Write-Host "  Dung ngay sua cua cac file loi tim duoc o lan kiem tra truoc."
    } else {
        $in = Read-Host "  Nhap ngay file bi sua (dd/MM/yyyy). De trong de huy"
        if (-not $in) { return }
        try { $dates = @([datetime]::ParseExact($in.Trim(), 'dd/MM/yyyy', $null)) }
        catch { Write-Host "  Ngay khong hop le." -ForegroundColor Red; return }
    }

    $uninstallKeys = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $apps = @(Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName })
    $downloads = Join-Path $env:USERPROFILE 'Downloads'

    foreach ($d in $dates) {
        Write-Host "`n  --- Ngay $($d.ToString('dd/MM/yyyy')) ---" -ForegroundColor Cyan
        $key = $d.ToString('yyyyMMdd')
        $found = @($apps | Where-Object { $_.InstallDate -eq $key })
        if ($found) {
            Write-Host "  Phan mem cai dat trong ngay:"
            $found | Format-Table @{n='Ten';e={$_.DisplayName}}, @{n='Hang';e={$_.Publisher}} -AutoSize | Out-Host
        } else {
            Write-Host "  Khong co phan mem nao duoc cai dat trong ngay nay."
        }
        $dl = @(Get-ChildItem $downloads -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime.Date -eq $d })
        if ($dl) {
            Write-Host "  File tai ve (Downloads) trong ngay:"
            $dl | Sort-Object LastWriteTime | Format-Table @{n='Gio';e={$_.LastWriteTime.ToString('HH:mm')}}, Name -AutoSize | Out-Host
        }
    }
    Write-Host "  Goi y: phan mem chinh hang (driver, Cloudflare...) thuong khong phai thu pham." -ForegroundColor Gray
    Write-Host "  Chu y ban crack, mod game, cong cu tang am thanh hoac chuong trinh khong ro nguon." -ForegroundColor Gray
}

function Invoke-BakManager {
    Write-Title "QUAN LY FILE .BAK"
    $baks = @(foreach ($f in $Folders) { Get-ChildItem -Path $f -Filter '*.dll*.bak' -File -ErrorAction SilentlyContinue })
    if (-not $baks) { Write-Host "  Khong co file .bak nao." -ForegroundColor Green; return }
    $baks | Format-Table FullName, @{n='KB';e={[math]::Round($_.Length/1KB,1)}}, LastWriteTime -AutoSize | Out-Host
    Write-Host "  1. Xoa tat ca file .bak (khi game da chay duoc)"
    Write-Host "  2. Khoi phuc tat ca ve ban cu (khi co phan mem bi loi sau khi sua)"
    Write-Host "  0. Quay lai"
    switch ((Read-Host "  Chon").Trim()) {
        '1' {
            if (-not (Confirm-Action "  Xoa $($baks.Count) file .bak")) { return }
            foreach ($b in $baks) {
                Remove-Item -LiteralPath $b.FullName -Force -ErrorAction SilentlyContinue
                if (Test-Path $b.FullName) { Grant-Access $b.FullName; Remove-Item -LiteralPath $b.FullName -Force -ErrorAction SilentlyContinue }
                if (Test-Path $b.FullName) { Write-Host "  [THAT BAI] $($b.FullName)" -ForegroundColor Red }
                else { Write-Host "  [DA XOA]   $($b.FullName)" -ForegroundColor Green }
            }
        }
        '2' {
            Write-Host "  Luu y: file cu co the la file bi sua, game se lai bao loi DirectX Runtime." -ForegroundColor Yellow
            if (-not (Confirm-Action "  Van khoi phuc")) { return }
            foreach ($b in $baks) {
                $origName = $b.Name -replace '(\.\d{8}-\d{6})?\.bak$', ''
                $origPath = Join-Path $b.DirectoryName $origName
                if (Test-Path $origPath) {
                    Grant-Access $origPath
                    Remove-Item -LiteralPath $origPath -Force -ErrorAction SilentlyContinue
                }
                Rename-Item -LiteralPath $b.FullName -NewName $origName -ErrorAction SilentlyContinue
                if (Test-Path $origPath) { Write-Host "  [DA KHOI PHUC] $origPath" -ForegroundColor Green }
                else { Write-Host "  [THAT BAI]     $origPath" -ForegroundColor Red }
            }
        }
    }
}

function Invoke-SystemRepair {
    Write-Title "SUA FILE HE THONG WINDOWS (sfc + DISM)"
    Write-Host "  Mat khoang 10-30 phut, can ket noi Internet. Khong tat cua so khi dang chay."
    if (-not (Confirm-Action "  Bat dau")) { return }
    DISM /Online /Cleanup-Image /RestoreHealth
    sfc /scannow
    Write-Host "`n  Xong. Hay khoi dong lai may." -ForegroundColor Green
}

function Invoke-AutoFix {
    Write-Title "SUA LOI TU DONG"
    Write-Host "  Script se lan luot:"
    Write-Host "    1. Kiem tra cac file DirectX ma Valorant can"
    Write-Host "    2. Doi ten file bi loi thanh .bak, tai va cai lai DirectX goc tu Microsoft"
    Write-Host "    3. Cai Visual C++ 2015-2022 neu dang thieu"
    if (-not (Confirm-Action "`n  Bat dau")) { return }

    $dxOk = Invoke-DxFix -NoConfirm

    $vc = Get-VcStatus
    if (@($vc.Values | Where-Object { -not $_ }).Count -gt 0) {
        Invoke-VcInstall
    } else {
        Write-Host "`n  Visual C++ 2015-2022 da du ca x64 va x86." -ForegroundColor Green
    }

    Write-Title "KET QUA"
    Show-ValorantAndVc
    if ($dxOk) {
        Write-Host "`n  Xong! Hay KHOI DONG LAI MAY roi mo Valorant." -ForegroundColor Green
        Write-Host "  Game chay duoc thi vao chuc nang 8 de xoa file .bak (neu co)." -ForegroundColor Gray
    } else {
        Write-Host "`n  Chua sua het. Thu: quet virus (6), kiem tra toan bo (3), sua file Windows (9)." -ForegroundColor Yellow
    }
}

# ======================= KHOI DONG =======================

if (-not (Test-Admin)) {
    Write-Host "`nCong cu nay can quyen admin." -ForegroundColor Yellow
    if (Confirm-Action "Mo lai PowerShell voi quyen admin") {
        if ($PSCommandPath) {
            Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoExit','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`""
        } else {
            $cmd = "irm '${ScriptUrl}?$(Get-Random)' | iex"
            Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoExit','-ExecutionPolicy','Bypass','-Command',$cmd
        }
        Write-Host "Da mo cua so moi. Ban co the dong cua so nay." -ForegroundColor Green
    }
    return
}

$osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$gpus   = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })

while ($true) {
    Clear-Host
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "   CONG CU SUA LOI 'DIRECTX RUNTIME' KHI MO VALORANT" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "   May : $env:COMPUTERNAME - $($osInfo.Caption) (build $($osInfo.BuildNumber))" -ForegroundColor Gray
    Write-Host "   GPU : $($gpus -join ', ')" -ForegroundColor Gray
    Write-Host ""
    Write-Host "   1. SUA LOI TU DONG (khuyen dung cho nguoi moi)" -ForegroundColor Green
    Write-Host ""
    Write-Host "   2. Kiem tra nhanh (file DirectX va Visual C++, ~1 phut)"
    Write-Host "   3. Kiem tra toan bo file DLL (5-15 phut)"
    Write-Host "   4. Sua file DirectX bi loi"
    Write-Host "   5. Cai / sua Visual C++ 2015-2022"
    Write-Host "   6. Quet virus bang Windows Defender"
    Write-Host "   7. Tim phan mem nghi da ghi de file"
    Write-Host "   8. Quan ly file .bak (xoa / khoi phuc)"
    Write-Host "   9. Sua file he thong Windows (sfc + DISM, 10-30 phut)"
    Write-Host ""
    Write-Host "   0. Thoat"
    Write-Host ""
    $choice = (Read-Host "   Go so roi bam Enter").Trim()

    switch ($choice) {
        '1' { Invoke-AutoFix;            Wait-Menu }
        '2' { Invoke-QuickCheck;         Wait-Menu }
        '3' { Invoke-FullCheck;          Wait-Menu }
        '4' { Invoke-DxFix | Out-Null;   Wait-Menu }
        '5' { Invoke-VcInstall;          Wait-Menu }
        '6' { Invoke-VirusScan;          Wait-Menu }
        '7' { Invoke-FindSource;         Wait-Menu }
        '8' { Invoke-BakManager;         Wait-Menu }
        '9' { Invoke-SystemRepair;       Wait-Menu }
        '0' {
            if (Test-Path $WorkDir) {
                Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "   Da xoa file tai ve tam ($WorkDir)." -ForegroundColor Gray
            }
            Write-Host "   Tam biet!" -ForegroundColor Cyan
            return
        }
    }
}
}
