<#
.SYNOPSIS
    WiFi 保活模块：防止插上有线后 WiFi 被系统自动断开。
.DESCRIPTION
    针对 USB WiFi 网卡（AIC8800D80 等）"连上有线就断 WiFi"的三层方案：
      1. fix     关闭 USB WiFi 的电源管理（根治，需管理员）
      2. fix     无线网卡省电模式设为"最高性能"（交流+直流，需管理员）
      3. monitor 保活循环：定时检查 WiFi，断开则自动重连；并定期复查电源修复（需管理员）
    可复用于多台 Windows：网卡/配置文件/电源设备全自动探测。

.ACTIONS
    status    只读查看 WiFi 状态与电源管理设置（无需管理员）
    fix       关闭电源管理 + 省电模式最高性能（需管理员，一次性）
    monitor   保活循环：断开自动重连 + 定期复查电源修复（前台运行，Ctrl+C 停止）
    install   注册开机自启计划任务运行 monitor（需管理员）
    uninstall 删除保活计划任务

.PARAMETER ProfileName
    WiFi 配置文件名称（如 WKU-VPN）。留空自动探测。

.PARAMETER IntervalSec
    monitor 检查间隔（秒），默认 15。

.PARAMETER FixIntervalSec
    monitor 定期复查电源修复的间隔（秒），默认 300。

.PARAMETER InstallDir
    install 时脚本自复制到的目录，默认 C:\sing-box。

.EXAMPLE
    .\wifi-keepalive.ps1 status
    .\wifi-keepalive.ps1 fix
    .\wifi-keepalive.ps1 monitor
    .\wifi-keepalive.ps1 install
    .\wifi-keepalive.ps1 uninstall
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('status', 'fix', 'monitor', 'install', 'uninstall')]
    [string]$Action = 'status',

    [string]$ProfileName = '',

    [int]$IntervalSec = 15,

    [int]$FixIntervalSec = 300,

    [string]$InstallDir = 'C:\sing-box'
)

$ErrorActionPreference = 'Stop'
$TaskName = 'wifi-keepalive'
$LogFile = Join-Path $PSScriptRoot 'wifi-keepalive.log'

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Log {
    param([string]$Msg)
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg
    Write-Host $line
    try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
}

function Get-WifiAdapter {
    $a = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object { $_.PhysicalMediaType -eq 'Native 802.11' } | Select-Object -First 1
    if (-not $a) { throw '未找到 WiFi 网卡（Native 802.11）。' }
    return $a
}

function Get-WifiProfileName {
    if ($ProfileName) { return $ProfileName }
    $out = netsh wlan show profiles 2>&1
    # 优先匹配"所有用户配置文件 : XXX" / "All User Profile : XXX"
    $line = $out | Where-Object { $_ -match '(所有用户配置文件|All User Profile)\s*:\s*(\S+)' } | Select-Object -First 1
    if ($line) {
        $m = [regex]::Match($line.ToString(), '(所有用户配置文件|All User Profile)\s*:\s*(\S+)')
        if ($m.Success) { return $m.Groups[2].Value }
    }
    # 兜底：任何"键: 值"形式的行，排除表头
    $line2 = $out | Where-Object { $_ -match ':\s*\S+\s*$' -and $_ -notmatch '^\s*接口|^\s*Interface|组策略|Group Policy' } | Select-Object -First 1
    if ($line2 -match ':\s*(\S+)\s*$') { return $Matches[1].Trim() }
    return $null
}

function Test-WifiConnected {
    $a = Get-WifiAdapter
    if ($a.Status -ne 'Up') { return $false }
    $ip = Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1
    return ($null -ne $ip)
}

function Get-WifiPnPInstanceId {
    $a = Get-WifiAdapter
    $pnp = Get-PnpDevice -Class Net -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -match [regex]::Escape($a.InterfaceDescription) -or $_.FriendlyName -match 'WiFi|Wireless|802\.11' } |
        Select-Object -First 1
    return $pnp.InstanceId
}

function Show-Status {
    $a = Get-WifiAdapter
    Write-Host ''
    Write-Host '=== WiFi 网卡 ===' -ForegroundColor Cyan
    Write-Host ("名称: {0}  状态: {1}  速率: {2}" -f $a.Name, $a.Status, $a.LinkSpeed)
    $ip = Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1
    Write-Host ("IPv4: {0}" -f $ip.IPAddress)

    Write-Host ''
    Write-Host '=== 配置文件 ===' -ForegroundColor Cyan
    netsh wlan show profiles 2>&1 | Select-String -Pattern ':\s*\S' | ForEach-Object { Write-Host $_.Line.Trim() }

    Write-Host ''
    Write-Host '=== USB WiFi 电源管理 ===' -ForegroundColor Cyan
    $id = Get-WifiPnPInstanceId
    $dev = Get-CimInstance -Namespace root\wmi -ClassName MSPower_DeviceEnable -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceName -match [regex]::Escape($id) }
    if ($dev) {
        Write-Host ("设备: {0}" -f $id)
        Write-Host ("允许系统关闭设备省电: {0}" -f $(if ($dev.Enable) { '是（开启，会断 WiFi）' } else { '否（已关闭，正常）' }))
    } else {
        Write-Host '未找到该 WiFi 的电源管理记录。'
    }

    Write-Host ''
    Write-Host '=== 无线省电模式 ===' -ForegroundColor Cyan
    powercfg /query SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 2>&1 |
        Select-String -Pattern '当前交流|当前直流' | ForEach-Object { Write-Host $_.Line.Trim() }
}

function Invoke-Fix {
    param([switch]$Quiet)
    # 1) 关闭 USB WiFi 电源管理（每次检查，防换 USB 口后新实例复发）
    $id = Get-WifiPnPInstanceId
    $dev = Get-CimInstance -Namespace root\wmi -ClassName MSPower_DeviceEnable -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceName -match [regex]::Escape($id) }
    if ($dev) {
        if ($dev.Enable) {
            $dev.Enable = $false
            Set-CimInstance -InputObject $dev
            Write-Log '已关闭 USB WiFi 电源管理（允许系统关闭设备 -> 关）'
        } elseif (-not $Quiet) {
            Write-Log 'USB WiFi 电源管理本已关闭，跳过。'
        }
    } else {
        Write-Log '警告：未找到 WiFi 电源管理记录，跳过该步。'
    }

    # 2) 无线省电模式设为最高性能（交流+直流，幂等）
    $sub = '19cbb8fa-5279-450e-9fac-8a3d5fedd0c1'
    $set = '12bbebe6-58d6-4636-95bb-3217ef867c1a'
    powercfg /setacvalueindex SCHEME_CURRENT $sub $set 0 | Out-Null
    powercfg /setdcvalueindex SCHEME_CURRENT $sub $set 0 | Out-Null
    powercfg /setactive SCHEME_CURRENT | Out-Null
    if (-not $Quiet) { Write-Log '无线省电模式已设为最高性能（交流+直流）。' }
}

function Invoke-Monitor {
    $prof = Get-WifiProfileName
    if (-not $prof) { Write-Log '警告：未探测到 WiFi 配置文件，重连将失败。' }
    Write-Log ("保活监控启动。配置文件='{0}'，间隔={1}s，修复复查间隔={2}s" -f $prof, $IntervalSec, $FixIntervalSec)
    $lastFix = [datetime]::MinValue
    while ($true) {
        try {
            # 定期复查电源修复（防换 USB 口后新实例复发）
            if ((Get-Date) - $lastFix -ge [TimeSpan]::FromSeconds($FixIntervalSec)) {
                try {
                    Invoke-Fix -Quiet
                } catch {
                    Write-Log ("电源修复复查失败: " + $_.Exception.Message)
                }
                $lastFix = Get-Date
            }
            if (-not (Test-WifiConnected)) {
                Write-Log '检测到 WiFi 断开，尝试重连...'
                if ($prof) {
                    netsh wlan connect name="$prof" | Out-Null
                } else {
                    # 无指定 profile 时，尝试自动连接（连接默认自动连接配置）
                    netsh wlan connect 2>&1 | Out-Null
                }
                Start-Sleep -Seconds 8
                if (Test-WifiConnected) {
                    Write-Log 'WiFi 已重新连接。'
                } else {
                    Write-Log '重连失败，下个周期重试。'
                }
            }
        } catch {
            Write-Log "监控异常: $_"
        }
        Start-Sleep -Seconds $IntervalSec
    }
}

# ---- 需要管理员的动作自动提权 ----
if ($Action -in @('fix', 'monitor', 'install', 'uninstall') -and -not (Test-Admin)) {
    Write-Host '该操作需要管理员权限，正在提权...'
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" $Action"
    exit 0
}

switch ($Action) {
    'status' {
        Show-Status
    }
    'fix' {
        Invoke-Fix
        Write-Host ''
        Write-Host '电源管理修复完成。建议再运行 install 注册保活任务。' -ForegroundColor Green
    }
    'monitor' {
        Invoke-Monitor
    }
    'install' {
        Invoke-Fix
        try {
            # 停掉旧版保活监控进程，避免重复实例
            Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                Where-Object { $_.CommandLine -match 'wifi-keepalive.*monitor' } |
                ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
            # 自复制到安装目录，保证计划任务路径稳定
            New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
            $dest = Join-Path $InstallDir 'wifi-keepalive.ps1'
            Copy-Item $PSCommandPath $dest -Force
            $taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' `
                -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dest`" monitor"
            $taskTrigger = New-ScheduledTaskTrigger -AtStartup
            $taskSettings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
                -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
            $taskPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
            Register-ScheduledTask -TaskName $TaskName -Action $taskAction -Trigger $taskTrigger -Settings $taskSettings -Principal $taskPrincipal -Force | Out-Null
            Start-ScheduledTask -TaskName $TaskName
            Write-Log "已注册并启动保活任务 '$TaskName'"
            Write-Host ''
            Write-Host '完成：电源管理已修复 + 保活任务已注册（开机自启）。' -ForegroundColor Green
            Write-Host '  验证: .\wifi-keepalive.ps1 status'
            Write-Host '  卸载: .\wifi-keepalive.ps1 uninstall'
        } catch {
            Write-Log ("注册保活任务失败: " + $_.Exception.Message)
            Write-Host ("注册保活任务失败: " + $_.Exception.Message) -ForegroundColor Red
        }
        Write-Host ''
        Read-Host '应用已安装（或已结束），请关闭此页面'
    }
    'uninstall' {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Log "已删除保活任务 '$TaskName'"
        Write-Host '已删除保活任务。'
    }
}
