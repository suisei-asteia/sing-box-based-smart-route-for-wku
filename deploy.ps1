<#
.SYNOPSIS
    sing-box 智能分流 部署脚本（有线直连 + WiFi VPN 分流）
.DESCRIPTION
    自动探测有线/WiFi 网卡与子网，生成配置，安装到 C:\sing-box，
    注册为"开机自启"计划任务（以 SYSTEM 运行，TUN 需管理员权限）。
    部署后效果：
      - 国内域名/IP -> 走有线（快速直连）
      - 境外/被墙    -> 走 WiFi VPN（学校 VPN 可打开所有外网）
    可复用于多台 Windows 设备：网卡名/子网/DNS 全自动探测，无需改代码。
.NOTES
    需管理员权限（脚本会自动提权）。卸载用 restore.ps1。
#>
[CmdletBinding()]
param(
    [string]$InstallDir = "C:\sing-box",
    [string]$SourceDir = "C:\Users\suisei\.openclaw\workspace\sing-box"
)

$ErrorActionPreference = 'Stop'
$TaskName = 'sing-box-smart-route'

# ---- 自提权 ----
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host '需要管理员权限，正在提权...'
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit 0
}

Write-Host '=== 1/5 探测网卡 ===' -ForegroundColor Cyan
$wired = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.PhysicalMediaType -eq '802.3' } | Select-Object -First 1
$wifi  = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.PhysicalMediaType -eq 'Native 802.11' } | Select-Object -First 1
if (-not $wired) { throw '未找到有线网卡(802.3)。' }
if (-not $wifi)  { throw '未找到 WiFi 网卡(Native 802.11)。' }
Write-Host ("有线: {0} (ifIndex {1})   WiFi: {2} (ifIndex {3})" -f $wired.Name, $wired.ifIndex, $wifi.Name, $wifi.ifIndex)

function Get-OnLinkSubnet([int]$ifIndex) {
    $r = Get-NetRoute -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.NextHop -eq '0.0.0.0' -and $_.DestinationPrefix -notin @('0.0.0.0/0','224.0.0.0/4','255.255.255.255/32') } |
        Where-Object { $_.DestinationPrefix -match '/(16|24|20|22|23|8)$' } |
        Select-Object -First 1
    return $r.DestinationPrefix
}
$wiredSubnet = Get-OnLinkSubnet $wired.ifIndex
$wifiSubnet  = Get-OnLinkSubnet $wifi.ifIndex
if (-not $wiredSubnet) { $wiredSubnet = '192.168.10.0/24' }
if (-not $wifiSubnet)  { $wifiSubnet  = '10.0.0.0/8' }
Write-Host ("有线子网: {0}   WiFi子网: {1}" -f $wiredSubnet, $wifiSubnet)

$wifiDns = ((Get-DnsClientServerAddress -InterfaceIndex $wifi.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses | Select-Object -First 1)
if (-not $wifiDns) { $wifiDns = '10.0.0.10' }
Write-Host ("WiFi DNS(用于境外解析): {0}" -f $wifiDns)

Write-Host '=== 2/5 生成配置 ===' -ForegroundColor Cyan
$cfg = @{
    log = @{ level = 'info'; timestamp = $true }
    dns = @{
        servers = @(
            @{ type = 'udp'; tag = 'cn-dns';   server = '223.5.5.5'; detour = 'direct-wired' },
            @{ type = 'udp'; tag = 'intl-dns'; server = $wifiDns;    detour = 'direct-wifi' },
            @{ type = 'local'; tag = 'local' }
        )
        rules = @(
            @{ rule_set = 'geosite-cn'; action = 'route'; server = 'cn-dns' },
            @{ action = 'route'; server = 'intl-dns' }
        )
        final = 'intl-dns'
        strategy = 'ipv4_only'
    }
    inbounds = @(
        @{
            type = 'tun'
            tag = 'tun-in'
            address = @('172.19.0.1/30', 'fdfe:dcba:9876::1/126')
            mtu = 1500
            auto_route = $true
            strict_route = $true
        }
    )
    outbounds = @(
        @{ type = 'direct'; tag = 'direct-wired'; bind_interface = $wired.Name },
        @{ type = 'direct'; tag = 'direct-wifi';  bind_interface = $wifi.Name },
        @{ type = 'block'; tag = 'block' }
    )
    route = @{
        rule_set = @(
            @{ type = 'local'; tag = 'geosite-cn'; format = 'binary'; path = "$InstallDir\geosite-cn.srs" },
            @{ type = 'local'; tag = 'geoip-cn';   format = 'binary'; path = "$InstallDir\geoip-cn.srs" }
        )
        rules = @(
            @{ inbound = 'tun-in'; action = 'sniff'; timeout = '1s' },
            @{ ip_cidr = @($wiredSubnet); outbound = 'direct-wired' },
            @{ ip_cidr = @($wifiSubnet);  outbound = 'direct-wifi' },
            @{ rule_set = 'geoip-cn'; outbound = 'direct-wired' },
            @{ rule_set = 'geosite-cn'; outbound = 'direct-wired' },
            @{ outbound = 'direct-wifi' }
        )
        final = 'direct-wifi'
        default_domain_resolver = 'intl-dns'
        auto_detect_interface = $false
    }
}

Write-Host '=== 3/5 复制文件到安装目录 ===' -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
foreach ($f in @('sing-box.exe', 'wintun.dll', 'geosite-cn.srs', 'geoip-cn.srs')) {
    $src = Join-Path $SourceDir $f
    if (-not (Test-Path $src)) { throw "缺少源文件: $src" }
    Copy-Item $src (Join-Path $InstallDir $f) -Force
}
$cfgPath = Join-Path $InstallDir 'config.json'
$json = $cfg | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($cfgPath, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "配置写入: $cfgPath"

Write-Host '=== 4/5 校验配置 ===' -ForegroundColor Cyan
& (Join-Path $InstallDir 'sing-box.exe') check -c $cfgPath -D $InstallDir
if ($LASTEXITCODE -ne 0) { throw "配置校验失败" }
Write-Host '配置校验通过。'

Write-Host '=== 5/5 注册计划任务(开机自启) ===' -ForegroundColor Cyan
$exe = Join-Path $InstallDir 'sing-box.exe'
$action = New-ScheduledTaskAction -Execute $exe -Argument "run -D `"$InstallDir`" -c `"$cfgPath`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
Write-Host "已注册计划任务 '$TaskName'。"

# 立即启动一次
Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 4
$info = Get-ScheduledTaskInfo -TaskName $TaskName
Write-Host ("任务状态: {0} (LastTaskResult={1})" -f $info.LastTaskResult, $info.LastRunTime)
Write-Host ''
Write-Host '部署完成。' -ForegroundColor Green
Write-Host '  验证: 访问 google.com 应走 WiFi；访问 baidu.com 应走有线。'
Write-Host '  卸载: 运行 restore.ps1'
