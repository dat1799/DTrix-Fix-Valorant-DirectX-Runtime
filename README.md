# DTrix – Fix Valorant DirectX Runtime

<div align="center">

**[🇺🇸 English](#english) · [🇻🇳 Tiếng Việt](#tiếng-việt)**

</div>

---

## English

### What is this?

A PowerShell tool that automatically detects and fixes **DirectX Runtime** errors when launching Valorant on Windows.

### How to run

Open **PowerShell** as **Administrator** (Start → search "powershell" → Run as administrator), paste:

```powershell
irm "https://gist.githubusercontent.com/dat1799/150903857de1134ffc2b4e8ba6c75e2e/raw/check-directx.en.ps1?$(Get-Random)" | iex
```

### Features

| # | Feature | Description |
|---|---------|-------------|
| 1 | **Auto Fix** | Renames broken DLL files, re-installs DirectX from Microsoft |
| 2 | Quick Check | Scans DirectX and VC++ files (~1 min) |
| 3 | Full Scan | Scans all DLLs in System32 + SysWOW64 (5–15 min) |
| 4 | Fix DirectX | Rename corrupt DLLs → re-install DirectX June 2010 |
| 5 | Install VC++ | Install/repair Visual C++ 2015–2022 (x64 + x86) |
| 6 | Virus Scan | Run Windows Defender quick or offline scan |
| 7 | Find Source | Find software installed on the same day files were modified |
| 8 | Manage .bak | Delete or restore renamed backup files |
| 9 | System Repair | Run `sfc /scannow` + `DISM /RestoreHealth` (10–30 min) |

### Requirements

- Windows 10 / 11
- PowerShell 5.1+
- Internet connection (for downloading DirectX and VC++ if needed)
- **Administrator privileges** (required)

---

## Tiếng Việt

### Công cụ này làm gì?

Script PowerShell tự động phát hiện và sửa lỗi **DirectX Runtime** khi mở Valorant trên Windows.

### Cách chạy

Mở **PowerShell** bằng **Run as Administrator** (Start → gõ "powershell" → Run as administrator), dán lệnh:

```powershell
irm "https://gist.githubusercontent.com/dat1799/150903857de1134ffc2b4e8ba6c75e2e/raw/check-directx.ps1?$(Get-Random)" | iex
```

### Chức năng

| # | Chức năng | Mô tả |
|---|-----------|-------|
| 1 | **Sửa tự động** | Đổi tên file DLL lỗi, cài lại DirectX từ Microsoft |
| 2 | Kiểm tra nhanh | Quét file DirectX và VC++ (~1 phút) |
| 3 | Kiểm tra toàn bộ | Quét toàn bộ DLL trong System32 + SysWOW64 (5–15 phút) |
| 4 | Sửa DirectX | Đổi tên DLL hỏng → cài lại DirectX June 2010 |
| 5 | Cài VC++ | Cài/sửa Visual C++ 2015–2022 (x64 + x86) |
| 6 | Quét virus | Dùng Windows Defender quét nhanh hoặc offline |
| 7 | Tìm nguồn gốc | Tìm phần mềm cài đúng ngày file bị sửa |
| 8 | Quản lý .bak | Xóa hoặc khôi phục file backup đã đổi tên |
| 9 | Sửa hệ thống | Chạy `sfc /scannow` + `DISM /RestoreHealth` (10–30 phút) |

### Yêu cầu

- Windows 10 / 11
- PowerShell 5.1+
- Kết nối Internet (khi cần tải DirectX và VC++)
- **Quyền Administrator** (bắt buộc)
