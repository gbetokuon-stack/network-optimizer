# Windows Network Optimizer (netopt)

Tool PowerShell toi uu mang cho Windows, giam lag khi choi game / stream / lam viec.

## Tinh nang

- **Scan** (`-Scan`): quet adapter, IP/DNS, ping, tien trinh ngon bang thong, dich vu nen, TCP global.
- **Optimize** (`-Optimize`): ap dung cac toi uu:
  - Tat Nagle (TcpAckFrequency=1, TCPNoDelay=1) giam do tre goi tin nho.
  - Loai 20% bang thong danh rieng cho QoS.
  - Tat proxy auto-detect (WPAD) tranh delay.
  - Bat TCP timestamps + Fast Open.
  - Dat DNS ve Cloudflare (1.1.1.1 / 1.0.0.1).
  - Dung & dat Manual cho BITS, Delivery Optimization, DiagTrack, SysMain, WSearch, UsoSvc.
  - Ket thuc tien trinh nen nang (Microsoft PC Manager, Omen Command Center...).
  - Xoa auto-start nang (Discord, Riot Client, Edge auto-launch, Cloudflare WARP).
  - Tat power saving tren NIC.
  - Flush DNS, don temp.
  - (Tuy chon) Reset Winsock + TCP/IP voi `-ResetStack`.
- **Restore** (`-Restore`): khoi phuc cai dat goc.

## Cach dung

Mo PowerShell **Run as Administrator**:

```powershell
# Quet
.\netopt.ps1 -Scan

# Toi uu (khong reset stack)
.\netopt.ps1 -Optimize

# Toi uu + reset stack (can reboot)
.\netopt.ps1 -Optimize -ResetStack

# Khoi phuc
.\netopt.ps1 -Restore
```

Script tu dong elevate neu chua co quyen admin.

## Luu y

- Backup registry duoc luu trong thu muc `backup/`.
- Mot so thay doi can khoi dong lai may (reset stack).
- Tat Windows Update services co the anh huong bao mat; script chi dat Manual, khong Disable.

## License

MIT
