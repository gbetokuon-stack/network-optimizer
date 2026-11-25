<#
.SYNOPSIS
    Windows Network Optimizer - giam lag, toi uu mang cho game/streaming.

.DESCRIPTION
    Quet (scan) trang thai mang, toi uu (optimize) cac thong so Windows,
    va khoi phuc (restore) neu can. Chay voi quyen Administrator (tu dong elevate).

.PARAMETER Scan
    Quet va hien thi thong tin mang, dich vu, tien trinh ngon bang thong.

.PARAMETER Optimize
    Ap dung cac toi uu: DNS, Nagle, QoS, tat dich vu nen, don temp, flush DNS...

.PARAMETER Restore
    Khoi phuc cai dat goc tu ban sao luu.

.PARAMETER ResetStack
    Reset Winsock + TCP/IP (can khoi dong lai may).

.PARAMETER SetDns
    Dat DNS ve Cloudflare (1.1.1.1 / 1.0.0.1) tren adapter dang ket noi.

.EXAMPLE
    .\netopt.ps1 -Scan
    .\netopt.ps1 -Optimize
    .\netopt.ps1 -Optimize -ResetStack
    .\netopt.ps1 -Restore
#>

[CmdletBinding()]
param(
    [switch]$Scan,
    [switch]$Optimize,
    [switch]$Restore,
    [switch]$ResetStack,
    [switch]$SetDns = $true
)

# ---------- Elevation ----------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $args = "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    foreach ($k in $PSBoundParameters.Keys) { $args += " -$k" }
    Start-Process powershell -ArgumentList $args -Verb RunAs -Wait
    exit
}

$ErrorActionPreference = 'Continue'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BackupDir = Join-Path $ScriptDir 'backup'
$LogFile   = Join-Path $ScriptDir 'netopt.log'
if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }

function Write-Log {
    param([string]$Msg)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Msg"
    Add-Content -Path $LogFile -Value $line
    Write-Host $Msg
}

function Backup-RegistryKey {
    param([string]$Path, [string]$Name)
    $export = Join-Path $BackupDir ("{0}_{1}.reg" -f ($Name -replace '[^a-zA-Z0-9]','_'), (Get-Date -Format 'yyyyMMddHHmmss'))
    if (Test-Path $Path) {
        reg export $Path $export /y 2>&1 | Out-Null
    }
}

# ---------- Scan ----------
function Invoke-Scan {
    Write-Log "===== SCAN ====="
    Write-Host ""
    Write-Host "=== Adapter dang ket noi ===" -ForegroundColor Cyan
    Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object Name, InterfaceDescription, LinkSpeed | Format-Table -AutoSize

    Write-Host "=== IP / DNS ===" -ForegroundColor Cyan
    Get-NetIPConfiguration | Where-Object { $_.IPv4Address } | Select-Object InterfaceAlias, @{N='IPv4';E={$_.IPv4Address.IPAddress}}, @{N='Gateway';E={$_.IPv4DefaultGateway.NextHop}}, @{N='DNS';E={($_.DnsServer.ServerAddresses) -join ', '}} | Format-Table -AutoSize

    Write-Host "=== Ping ===" -ForegroundColor Cyan
    foreach ($t in @('192.168.1.1','1.1.1.1','google.com')) {
        $r = Test-Connection -ComputerName $t -Count 4 -ErrorAction SilentlyContinue
        if ($r) {
            $avg = [math]::Round(($r | Measure-Object -Property ResponseTime -Average).Average,1)
            $loss = 4 - ($r | Where-Object { $_.Status -eq 'Success' }).Count
            Write-Host ("  {0}: avg {1}ms, loss {2}/4" -f $t, $avg, $loss)
        } else {
            Write-Host ("  {0}: FAIL" -f $t)
        }
    }

    Write-Host ""
    Write-Host "=== Tien trinh dung nhieu CPU ===" -ForegroundColor Cyan
    Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 Name, Id, @{N='CPU(s)';E={[math]::Round($_.CPU,1)}}, @{N='MemMB';E={[math]::Round($_.WorkingSet/1MB,0)}} | Format-Table -AutoSize

    Write-Host "=== Ket noi TCP theo tien trinh ===" -ForegroundColor Cyan
    Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
        Group-Object OwningProcess | Sort-Object Count -Descending | Select-Object -First 12 |
        ForEach-Object {
            $p = Get-Process -Id $_.Name -ErrorAction SilentlyContinue
            [PSCustomObject]@{ PID=$_.Name; Name=$p.Name; Conns=$_.Count }
        } | Format-Table -AutoSize

    Write-Host "=== Dich vu ngon bang thong ===" -ForegroundColor Cyan
    foreach ($s in @('BITS','dosvc','DiagTrack','SysMain','WSearch','UsoSvc','wuauserv')) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($svc) { Write-Host ("  {0}: {1} ({2})" -f $svc.Name, $svc.Status, $svc.StartType) }
    }

    Write-Host "=== TCP global ===" -ForegroundColor Cyan
    netsh int tcp show global | Select-String -Pattern "State|Level|Provider|Capability|Timestamps|Retransmissions|RTO|Open" | ForEach-Object { Write-Host ("  " + $_.Line.Trim()) }

    Write-Host ""
    Write-Log "Scan hoan tat."
}

# ---------- Optimize ----------
$HeavyServices = @('BITS','dosvc','DiagTrack','SysMain','WSearch','UsoSvc')
$KillProcesses = @('MSPCManager','MSPCManagerCore','OmenCommandCenterBackground','OmenCommandCenter')
$StartupRemove = @('Discord','RiotClient','MicrosoftEdgeAutoLaunch_5EFC0ECB77A7585FE9DCDD0B2E946A2B')

function Invoke-Optimize {
    Write-Log "===== OPTIMIZE ====="

    # Backup registry
    Write-Log "Backup registry Run keys..."
    Backup-RegistryKey -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'Run_HKLM'
    Backup-RegistryKey -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'Run_HKCU'

    # 1. Nagle
    Write-Log "Tat Nagle (TcpAckFrequency=1, TCPNoDelay=1)..."
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
    foreach ($a in $adapters) {
        $path = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\' + $a.InterfaceGuid
        if (Test-Path $path) {
            Set-ItemProperty -Path $path -Name 'TcpAckFrequency' -Value 1 -Type DWord -Force
            Set-ItemProperty -Path $path -Name 'TCPNoDelay' -Value 1 -Type DWord -Force
            Write-Log ("  " + $a.Name + ": OK")
        }
    }

    # 2. QoS
    Write-Log "QoS: bo 20% bang thong danh rieng..."
    $qosPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched'
    if (-not (Test-Path $qosPath)) { New-Item -Path $qosPath -Force | Out-Null }
    Set-ItemProperty -Path $qosPath -Name 'NonBestEffortLimit' -Value 0 -Type DWord -Force
    Write-Log "  OK"

    # 3. Proxy auto-detect off
    Write-Log "Tat proxy auto-detect (WPAD)..."
    $inet = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    Set-ItemProperty -Path $inet -Name 'AutoDetect' -Value 0 -Type DWord -Force
    Write-Log "  OK"

    # 4. TCP global
    Write-Log "TCP global: timestamps + fastopen..."
    netsh int tcp set global timestamps=enabled 2>&1 | Out-Null
    netsh int tcp set global fastopen=enabled 2>&1 | Out-Null
    Write-Log "  OK"

    # 5. DNS
    if ($SetDns) {
        Write-Log "Dat DNS Cloudflare (1.1.1.1 / 1.0.0.1)..."
        foreach ($a in $adapters) {
            try {
                Set-DnsClientServerAddress -InterfaceAlias $a.Name -ServerAddresses @('1.1.1.1','1.0.0.1') -ErrorAction Stop
                Write-Log ("  " + $a.Name + ": OK")
            } catch {
                Write-Log ("  " + $a.Name + ": " + $_.Exception.Message)
            }
        }
    }

    # 6. Services
    Write-Log "Dung & dat Manual cho dich vu nen..."
    foreach ($s in $HeavyServices) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($svc) {
            try { Stop-Service -Name $s -Force -ErrorAction SilentlyContinue } catch {}
            try { Set-Service -Name $s -StartupType Manual -ErrorAction SilentlyContinue } catch {}
            Write-Log ("  " + $s + ": OK")
        }
    }

    # 7. Kill heavy processes
    Write-Log "Ket thuc tien trinh nang..."
    foreach ($n in $KillProcesses) {
        Get-Process -Name $n -ErrorAction SilentlyContinue | ForEach-Object {
            try { Stop-Process -Id $_.Id -Force; Write-Log ("  Killed " + $_.Name) } catch { Write-Log ("  Khong the kill " + $_.Name) }
        }
    }

    # 8. Remove startup entries
    Write-Log "Xoa auto-start nang..."
    $runHKCU = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $runHKLM = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
    foreach ($name in $StartupRemove) {
        if (Test-Path $runHKCU) { Remove-ItemProperty -Path $runHKCU -Name $name -ErrorAction SilentlyContinue }
    }
    Remove-ItemProperty -Path $runHKLM -Name 'CloudflareWARP' -ErrorAction SilentlyContinue
    Write-Log "  OK"

    # 9. NIC power management
    Write-Log "Tat power saving tren NIC..."
    foreach ($a in $adapters) {
        try {
            Set-NetAdapterPowerManagement -Name $a.Name -AllowComputerToTurnOffDevice Disabled -ErrorAction Stop
            Write-Log ("  " + $a.Name + ": OK")
        } catch {
            Write-Log ("  " + $a.Name + ": " + $_.Exception.Message)
        }
    }

    # 10. Flush DNS
    Write-Log "Flush DNS..."
    ipconfig /flushdns 2>&1 | Out-Null
    ipconfig /registerdns 2>&1 | Out-Null
    Write-Log "  OK"

    # 11. Clear temp
    Write-Log "Don temp..."
    foreach ($p in @($env:TEMP, 'C:\Windows\Temp')) {
        if (Test-Path $p) {
            Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Log "  OK"

    # 12. Reset stack (optional)
    if ($ResetStack) {
        Write-Log "Reset Winsock + TCP/IP (can reboot)..."
        netsh winsock reset 2>&1 | Out-Null
        netsh int ip reset 2>&1 | Out-Null
        Write-Log "  OK - hay khoi dong lai may."
    }

    Write-Log "===== OPTIMIZE HOAN TAT ====="
    Write-Host ""
    Write-Host "Goi y: khoi dong lai may de ap dung day du (neu dung -ResetStack)." -ForegroundColor Yellow
}

# ---------- Restore ----------
function Invoke-Restore {
    Write-Log "===== RESTORE ====="
    # Re-enable services
    foreach ($s in $HeavyServices) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($svc) {
            try { Set-Service -Name $s -StartupType Automatic -ErrorAction SilentlyContinue } catch {}
            Write-Log ("  " + $s + ": Automatic")
        }
    }
    # Remove Nagle overrides
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
    foreach ($a in $adapters) {
        $path = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\' + $a.InterfaceGuid
        if (Test-Path $path) {
            Remove-ItemProperty -Path $path -Name 'TcpAckFrequency' -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $path -Name 'TCPNoDelay' -ErrorAction SilentlyContinue
        }
    }
    # QoS remove
    Remove-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched' -Recurse -Force -ErrorAction SilentlyContinue
    # Proxy auto-detect back on
    $inet = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    Set-ItemProperty -Path $inet -Name 'AutoDetect' -Value 1 -Type DWord -Force
    # DNS back to DHCP
    foreach ($a in $adapters) {
        try { Set-DnsClientServerAddress -InterfaceAlias $a.Name -ResetServerAddresses -ErrorAction SilentlyContinue } catch {}
    }
    Write-Log "Restore hoan tat. (Startup entries can khoi phuc thu cong tu backup/)"
}

# ---------- Dispatch ----------
if ($Restore) {
    Invoke-Restore
} elseif ($Optimize) {
    Invoke-Optimize
} else {
    Invoke-Scan
}
