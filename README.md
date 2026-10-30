# DTrix DirectX Tool

> Kiểm tra và sửa DirectX / Valorant DLL integrity trên Windows.  
> Phân phối qua GitHub với xác minh SHA-256 và Authenticode.

---

## Chạy nhanh (người dùng)

Mở **PowerShell** (không cần Admin để chỉ kiểm tra):

```powershell
irm "https://gist.githubusercontent.com/dat1799/edec51f0e3e81e2b4c042e2bc896dd4d/raw/launcher.ps1" | iex
```

> **Lưu ý:** Nếu muốn dùng chức năng tự sửa (`-Fix`), chạy PowerShell bằng **Run as Administrator**.

---

## Chức năng

| Chế độ | Mô tả |
|--------|-------|
| Scan only | Kiểm tra chữ ký tất cả DLL trong `System32` + `SysWOW64` |
| Valorant check | Xác minh `xinput1_3.dll`, `X3DAudio1_7.dll` |
| VC++ check | Kiểm tra Visual C++ 2015–2022 Runtime (x64 + x86) |
| System info | OS build number, GPU, driver version |
| CSV report | Xuất báo cáo ra Desktop |
| `-Fix` | Đổi tên DirectX legacy DLL bị hỏng → chạy lại DXSETUP |
| `-Force` | Không hỏi xác nhận khi sửa |

---

## Cấu trúc dự án

```
DirectX-Tool/
├── launcher/
│   └── launcher.ps1          ← Upload lên GitHub Gist (public)
├── payload/
│   └── check-directx.ps1     ← Source gốc
├── manifest/
│   └── manifest.json         ← Commit vào repo (branch main)
├── build/
│   └── build.ps1             ← Dev only
├── security/
│   └── verify.ps1            ← Dev only
└── README.md
```

---

## Hướng dẫn Dev – Phát hành phiên bản mới

### Bước 1: Chỉnh sửa payload

Chỉnh sửa `payload/check-directx.ps1` theo nhu cầu.

### Bước 2: Build

```powershell
cd DirectX-Tool\build

# Build thông thường
.\build.ps1 -Version "1.1.0" -Force

# Build + ký số (nếu có Code Signing Certificate)
.\build.ps1 -Version "1.1.0" -Sign -Force
```

Artifacts xuất ra: `build/dist/`

### Bước 3: Verify độc lập

```powershell
cd DirectX-Tool\security

.\verify.ps1 `
  -PayloadPath "..\build\dist\check-directx.ps1" `
  -ManifestPath "..\build\dist\manifest.json"
```

### Bước 4: Commit manifest

```powershell
git add manifest/manifest.json
git commit -m "Release v1.1.0"
git push origin main
```

### Bước 5: Tạo GitHub Release

Cần cài [GitHub CLI](https://cli.github.com/):

```powershell
gh release create v1.1.0 `
  --title "DTrix DirectX Tool v1.1.0" `
  --notes "Mô tả thay đổi" `
  "build\dist\check-directx.ps1"
```

Hoặc tạo thủ công trên GitHub:
1. Vào **Releases → Draft a new release**
2. Tag: `v1.1.0`
3. Upload file `build\dist\check-directx.ps1`
4. Publish

### Bước 6: Cập nhật Gist launcher (chỉ khi launcher thay đổi)

1. Mở **gist.github.com**
2. Tìm Gist chứa `launcher.ps1`
3. Paste nội dung từ `build/dist/launcher.ps1`

---

## Hướng dẫn Dev – Thiết lập lần đầu

### 1. Tạo GitHub Gist cho launcher

1. Truy cập [gist.github.com](https://gist.github.com)
2. Tạo **Public Gist** mới, filename: `launcher.ps1`
3. Paste toàn bộ nội dung `launcher/launcher.ps1`
4. Lấy URL dạng:
   ```
   https://gist.githubusercontent.com/dat1799/GIST_ID/raw/launcher.ps1
   ```

> **Tại sao Public Gist?** `irm ... | iex` cần URL công khai không yêu cầu auth.  
> **Không dùng Secret Gist như biện pháp bảo mật** – URL chỉ là obscure, không phải private.

### 2. Cấu hình launcher.ps1

Trong `launcher/launcher.ps1`, đảm bảo `CONFIG` đúng:

```powershell
$script:CONFIG = @{
    ManifestUrl = 'https://raw.githubusercontent.com/dat1799/Check-Valorant-DirectX-Runtime/main/manifest/manifest.json'
    # ...
}
```

### 3. Build và phát hành lần đầu

```powershell
.\build\build.ps1 -Version "1.0.0" -Force
.\security\verify.ps1 -PayloadPath ".\build\dist\check-directx.ps1" -ManifestPath ".\build\dist\manifest.json"
# Nếu verify thành công → commit + release
```

---

## Bảo mật – Những gì được bảo vệ và không thể bảo vệ

### ✔ Được bảo vệ

| Bảo vệ | Cơ chế |
|--------|--------|
| File bị sửa / tamper | SHA-256 hash so với manifest |
| File bị thay thế | Authenticode Signature (nếu có cert) |
| MITM khi tải | Bắt buộc HTTPS (TLS 1.2+) |
| Manifest bị sửa | Cấu trúc bắt buộc, validate trước khi dùng |
| Payload lỗi download | Retry 3 lần + timeout |
| Phiên bản launcher cũ | `minLauncherVersion` trong manifest |

### ✘ Không thể bảo vệ hoàn toàn

| Giới hạn | Lý do kỹ thuật |
|----------|---------------|
| **Ẩn source code** | PowerShell phải giải mã và thực thi trên CPU của user – công cụ như Process Monitor / Script Block Logging có thể capture |
| **Chống decompile** | File `.ps1` là plain text; ngay cả compile sang `.exe` vẫn có thể decompile bằng ILSpy |
| **Key AES bí mật** | Nếu encrypt payload, key phải nằm trong launcher → user lấy được key = lấy được source |
| **DRM thực sự** | Không tồn tại cho PowerShell scripts chạy local |

> **Kết luận:** Hệ thống này đảm bảo **integrity** (không bị sửa) và **authenticity** (đến từ bạn) – đây là mục tiêu thực tế. Source code protection ở mức hạn chế người dùng thông thường, không phải người có kỹ thuật cao.

---

## Yêu cầu

- Windows 10/11
- PowerShell 5.1+ hoặc PowerShell 7+
- Kết nối Internet (lần đầu chạy)
- Quyền Administrator (chỉ khi dùng `-Fix`)

---

## Repo

[github.com/dat1799/Check-Valorant-DirectX-Runtime](https://github.com/dat1799/Check-Valorant-DirectX-Runtime)

