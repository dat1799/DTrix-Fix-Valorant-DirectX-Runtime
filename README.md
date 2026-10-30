# DTrix – Fix Valorant DirectX Runtime

<div align="center">

**[🇺🇸 English](#english) · [🇻🇳 Tiếng Việt](#tiếng-việt)**

</div>

---

## English

### What is this?

A lightweight PowerShell tool that automatically detects and fixes **DirectX Runtime** errors when launching Valorant on Windows.

### How to run

Open **PowerShell** as **Administrator** (Start → search "powershell" → Run as administrator), paste and run:

```powershell
irm "https://gist.githubusercontent.com/dat1799/150903857de1134ffc2b4e8ba6c75e2e/raw/check-directx.ps1?$(Get-Random)" | iex
```

> **Tip:** You can switch between English and Vietnamese anytime by pressing **`L`** in the main menu!

### Features

| # | Feature | Description |
|---|---------|-------------|
| 1 | **Auto Fix** | Renames corrupt DLL files, downloads & installs official DirectX from Microsoft |
| 2 | Quick Check | Scans DirectX and Visual C++ files (~1 min) |
| 3 | Full DLL Scan | Scans all DLLs in System32 + SysWOW64 (5–15 min) |
| 4 | Fix DirectX | Rename corrupt DLLs → re-install DirectX June 2010 |
| 5 | Install / Repair VC++ | Install or repair Visual C++ 2015–2022 (x64 + x86) |
| 6 | Virus Scan | Run Windows Defender quick or offline scan |
| 7 | Find Source | Identify software installed on the date files were modified |
| 8 | Manage .bak | Delete or restore backup DLL files |
| 9 | Repair Windows | Run `sfc /scannow` + `DISM /RestoreHealth` (10–30 min) |
| L | **Language** | Switch language between English and Tiếng Việt |

### Requirements

- Windows 10 / 11
- PowerShell 5.1+
- Internet connection
- **Administrator privileges**

---

## Tiếng Việt

### Giới thiệu

Công cụ PowerShell tự động kiểm tra và sửa triệt để lỗi **DirectX Runtime** khi mở Valorant trên Windows.

### Cách chạy

Mở **PowerShell** bằng **Run as Administrator** (Start → gõ "powershell" → Run as administrator), dán lệnh:

```powershell
irm "https://gist.githubusercontent.com/dat1799/150903857de1134ffc2b4e8ba6c75e2e/raw/check-directx.ps1?$(Get-Random)" | iex
```

> **Mẹo:** Bạn có thể chuyển đổi qua lại giữa Tiếng Việt và Tiếng Anh bất kỳ lúc nào bằng phím **`L`** trong menu!

### Chức năng

| # | Chức năng | Mô tả |
|---|-----------|-------|
| 1 | **Sửa tự động** | Tự động đổi tên file DLL lỗi, tải và cài lại DirectX gốc từ Microsoft |
| 2 | Kiểm tra nhanh | Quét nhanh các file DirectX và Visual C++ (~1 phút) |
| 3 | Kiểm tra toàn bộ | Quét chữ ký số toàn bộ DLL trong System32 + SysWOW64 (5–15 phút) |
| 4 | Sửa file DirectX | Đổi tên DLL hỏng → cài lại DirectX June 2010 |
| 5 | Cài / Sửa VC++ | Cài hoặc sửa Visual C++ 2015–2022 (x64 + x86) |
| 6 | Quét virus | Chạy Windows Defender quét nhanh hoặc quét offline khi khởi động |
| 7 | Tìm nguồn gốc | Tìm phần mềm được cài đặt đúng ngày file DLL bị sửa đổi |
| 8 | Quản lý .bak | Xóa dọn dẹp hoặc khôi phục lại các file backup cũ |
| 9 | Sửa hệ thống | Chạy sửa chữa Windows bằng `sfc /scannow` + `DISM /RestoreHealth` |
| L | **Đổi ngôn ngữ** | Chuyển đổi ngôn ngữ Tiếng Việt ↔ Tiếng Anh |

### Yêu cầu

- Windows 10 / 11
- PowerShell 5.1+
- Có kết nối Internet
- **Quyền Administrator**
