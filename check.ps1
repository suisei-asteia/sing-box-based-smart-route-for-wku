<#
.SYNOPSIS
    sing-box 智能分流 部署前环境检查脚本
.DESCRIPTION
    只读检查，无需管理员权限。逐项验证部署所需条件：
      - 第三方二进制文件是否齐全
      - 有线/WiFi 网卡是否存在
      - WiFi 是否已连接
      - 管理员权限
      - sing-box.exe 是否可用
    每项输出 [OK] 或 [缺失/警告]，最后给出总结。
    运行结束后停留等待手动关闭。
#>
[CmdletBinding()]
param(
    [string]$SourceDir = ""
)

$ErrorActionPreference = 'Continue'
if ([string]::IsNullOrWhiteSpace($SourceDir)) { $SourceDir = $PSScriptRoot }

function Write-OK([string]$Msg) { Write-Host ("  [OK]   " + $Msg) -ForegroundColor Green }
function Write-Bad([string]$Msg) { Write-Host ("  [缺失] " + $Msg) -ForegroundColor Red }
function Write-Warn([string]$Msg) { Write-Host ("  [警告] " + $Msg) -ForegroundColor Yellow }

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host '  sing-box 智能分流 - 环境检查' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

$fail = 0

Write-Host ''
Write-Host '【1】第三方二进制文件' -ForegroundColor Cyan
$files = @('sing-box.exe', 'wintun.dll', 'geosite-cn.srs', 'geoip-cn.srs')
foreach ($f in $files) {
    $p = Join-Path $SourceDir $f
    if (Test-Path $p) {
        $size = (Get-Item $p).Length
        Write-OK ("{0}  ({1:N0} 字节)" -f $f, $size)
    } else {
        Write-Bad $f
        $fail++
    }
}
if ($fail -gt 0) {
    Write-Warn '缺少第三方文件。请按 README「第三方依赖」章节下载并放到本目录。'
}

Write-Host ''
Write-Host '【2】网卡' -ForegroundColor Cyan
$wired = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.PhysicalMediaType -eq '802.3' } | Select-Object -First 1
$wifi  = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.PhysicalMediaType -eq 'Native 802.11' } | Select-Object -First 1
if ($wired) { Write-OK ("有线网卡: {0} (状态 {1})" -f $wired.Name, $wired.Status) }
else { Write-Bad '未找到有线网卡(802.3)'; $fail++ }
if ($wifi) { Write-OK ("WiFi 网卡: {0} (状态 {1})" -f $wifi.Name, $wifi.Status) }
else { Write-Bad '未找到 WiFi 网卡(Native 802.11)'; $fail++ }

Write-Host ''
Write-Host '【3】WiFi 连接状态' -ForegroundColor Cyan
if ($wifi) {
    if ($wifi.Status -eq 'Up') {
        $ip = (Get-NetIPAddress -InterfaceIndex $wifi.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1).IPAddress
        Write-OK ("WiFi 已连接，IP: {0}" -f $ip)
    } else {
        Write-Warn ("WiFi 未连接（状态: {0}）。部署前请先连接 WiFi VPN，否则境外流量无出口。" -f $wifi.Status)
    }
}

Write-Host ''
Write-Host '【4】管理员权限' -ForegroundColor Cyan
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) { Write-OK '当前已具备管理员权限' }
else { Write-Warn '当前非管理员。运行 deploy 时会自动弹 UAC 提权，点"是"即可。' }

Write-Host ''
Write-Host '【5】sing-box 可用性' -ForegroundColor Cyan
$sb = Join-Path $SourceDir 'sing-box.exe'
if (Test-Path $sb) {
    $v = & $sb version 2>&1 | Select-Object -First 1
    Write-OK ("sing-box 版本: {0}" -f $v)
} else {
    Write-Bad 'sing-box.exe 不存在，无法检测版本'
}

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
if ($fail -eq 0) {
    Write-Host '  检查通过，可以开始部署。' -ForegroundColor Green
} else {
    Write-Host ("  有 {0} 项缺失，请先处理后再部署。" -f $fail) -ForegroundColor Red
}
Write-Host '========================================' -ForegroundColor Cyan

Write-Host ''
Read-Host '检查完毕，请关闭此页面'
