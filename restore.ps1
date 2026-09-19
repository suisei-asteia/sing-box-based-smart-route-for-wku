<#
.SYNOPSIS
    sing-box 智能分流 一键还原/卸载脚本
.DESCRIPTION
    停止并删除计划任务，结束 sing-box 进程，可选删除安装目录。
    还原后系统回到部署前状态（无 TUN、无分流）。
.NOTES
    需管理员权限（脚本会自动提权）。
#>
[CmdletBinding()]
param(
    [string]$InstallDir = "C:\sing-box",
    [switch]$RemoveFiles
)
$ErrorActionPreference = 'Stop'
$TaskName = 'sing-box-smart-route'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host '需要管理员权限，正在提权...'
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit 0
}

Write-Host '=== 停止并删除计划任务 ===' -ForegroundColor Cyan
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Write-Host "已删除计划任务 '$TaskName'。"

Write-Host '=== 结束 sing-box 进程 ===' -ForegroundColor Cyan
Get-Process sing-box -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Write-Host '已结束 sing-box 进程。'

if ($RemoveFiles) {
    Write-Host '=== 删除安装目录 ===' -ForegroundColor Cyan
    if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force }
    Write-Host "已删除 $InstallDir"
}

Write-Host ''
Write-Host '还原完成。系统已回到部署前状态。' -ForegroundColor Green
