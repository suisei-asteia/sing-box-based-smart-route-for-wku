# 双网卡智能分流 + WiFi 保活

一套 Windows 工具：让同时接「有线网 + WiFi VPN」的电脑自动分流，并在 WiFi 被系统误关时自动保活重连。

## 它能解决什么问题

| 场景 | 结果 |
|------|------|
| 访问国内网站/服务 | 自动走**有线**（高速、低延迟） |
| 访问境外/被墙网站（Google、YouTube 等） | 自动走 **WiFi VPN**（学校 VPN 能打开所有外网资源） |
| 插上有线后 WiFi 被系统"省电"自动断开 | 自动重连 + 关闭电源管理（根治） |
| 换 USB 口后电源管理恢复默认 | 保活循环定期复查，自动重新修复 |

## 适用条件（Prerequisites）

- **Windows 10/11**（AMD64）
- 机器同时具备两张物理网卡：
  - 一张**有线网卡**（Ethernet，802.3）
  - 一张**WiFi 网卡**（Native 802.11，本方案针对 USB WiFi 网卡优化）
- WiFi 需连接一个**能访问境外资源的网络**（如学校 VPN 的 WiFi，SSID 形如 `WKU-VPN`）
- 需要**管理员权限**（安装时会弹 UAC）
- 首次运行需要联网（下载规则集文件）

> ⚠️ **关键前提**：WiFi 必须保持连接。整套分流的境外流量出口就是 WiFi，如果 WiFi 断开，境外网站会打不开（这不是 bug，是出口没了）。保活模块正是为此兜底。

## 第三方依赖（使用前必须先准备）

本项目脚本不自带第三方二进制，**使用前需手动下载并放到项目目录**：

| 文件 | 大小 | 下载地址 | 许可证 |
|------|------|----------|--------|
| `sing-box.exe` | ~82MB | https://github.com/SagerNet/sing-box/releases（选 `windows-amd64.zip`） | GPLv3 |
| `wintun.dll` | ~430KB | https://www.wintun.net/（解压后取 `bin/amd64/wintun.dll`） | WireGuard，可再分发 |
| `geosite-cn.srs` | ~56KB | https://github.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs | 见源仓库 |
| `geoip-cn.srs` | ~34KB | https://github.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs | 见源仓库 |

> 缺这些文件时，`deploy.ps1` 会在复制阶段报错提示。规则集（.srs）也可由脚本自动下载，但 sing-box.exe 和 wintun.dll 必须手动放置。

## 文件清单

| 文件 | 说明 |
|------|------|
| `0-check.bat` | 部署前环境检查启动器（双击运行 check.ps1） |
| `1-deploy.bat` | 一键部署启动器（双击运行 deploy.ps1） |
| `2-wifi-keepalive.bat` | WiFi 保活安装启动器（双击运行 install） |
| `check.ps1` | 部署前环境检查：文件/网卡/WiFi/权限/sing-box 版本 |
| `deploy.ps1` | 一键部署：探测网卡 → 生成配置 → 安装到 `C:\sing-box` → 注册开机自启任务 |
| `restore.ps1` | 一键还原：删除任务、结束进程，恢复到部署前状态 |
| `wifi-keepalive.ps1` | WiFi 保活模块：关闭电源管理 + 断开自动重连 + 定期复查修复 |
| `config.json` | 分流配置（模板，`deploy.ps1` 会按本机实际情况重新生成） |
| `sing-box.exe` | sing-box 核心程序（v1.14.1，第三方，需自行下载） |
| `wintun.dll` | sing-box TUN 模式所需的虚拟网卡驱动（第三方，需自行下载） |
| `geosite-cn.srs` / `geoip-cn.srs` | 国内域名/IP 规则集（SagerNet 维护，需自行下载） |

## 安装步骤

> **最简单的方式：双击 .bat 文件**（推荐，适合不熟悉 PowerShell 的人）
>
> 项目里已经备好三个启动器，双击即可运行：
> - `0-check.bat` —— 部署前环境检查（只读，先跑这个）
> - `1-deploy.bat` —— 部署智能分流（对应 `deploy.ps1`）
> - `2-wifi-keepalive.bat` —— 安装 WiFi 保活（对应 `wifi-keepalive.ps1 install`）
>
> 运行时会弹 UAC 提权框，点"是"即可。脚本跑完会停留等手动关闭，不会闪退。

### 0. 环境检查（推荐先做）

**方式 A（双击）**：双击 `0-check.bat`

**方式 B（命令行）**：

```powershell
.\check.ps1
```

逐项检查第三方文件、网卡、WiFi 连接、管理员权限、sing-box 版本。全部 [OK] 再继续部署。

### 1. 部署智能分流

**方式 A（双击）**：双击 `1-deploy.bat`

**方式 B（命令行）**：

```powershell
cd <项目目录>
.\deploy.ps1
```

脚本会自动：探测有线/WiFi 网卡名、子网、WiFi DNS → 生成配置 → 复制文件到 `C:\sing-box` → 校验 → 注册「开机自启」计划任务 `sing-box-smart-route` → 立即启动。

首次运行会弹 UAC，点"是"。

### 2. 部署 WiFi 保活

**方式 A（双击）**：双击 `2-wifi-keepalive.bat`

**方式 B（命令行）**：

```powershell
.\wifi-keepalive.ps1 install
```

脚本会自动：关闭 USB WiFi 的电源管理 → 无线省电模式设为最高性能 → 注册「开机自启」保活任务 `wifi-keepalive` → 立即启动。

同样会弹 UAC。

### 3. 验证

```powershell
# 国内走有线、境外走 WiFi
curl.exe -s -o NUL -w "%{http_code}`n" https://www.baidu.com    # 应返回 200
curl.exe -s -o NUL -w "%{http_code}`n" https://www.google.com  # 应返回 3xx/200

# 查看 WiFi 保活状态
.\wifi-keepalive.ps1 status
```

## 卸载 / 还原

```powershell
# 还原智能分流（删任务 + 结束进程）
.\restore.ps1

# 卸载 WiFi 保活（删任务）
.\wifi-keepalive.ps1 uninstall

# 卸载并删除安装目录 C:\sing-box
.\restore.ps1 -RemoveFiles
```

> 注意：`restore.ps1` 和 `wifi-keepalive.ps1 uninstall` 是两套独立任务，需分别卸载。

## 工作原理

### 智能分流（sing-box TUN 模式）

- sing-box 创建虚拟网卡 `tun0`，以透明方式接管所有流量
- 两个直连出口：`direct-wired`（绑有线网卡）、`direct-wifi`（绑 WiFi 网卡）
- 路由规则：`geosite-cn` / `geoip-cn` 规则集命中的流量 → 有线；其余（境外）→ WiFi VPN
- DNS 分流：国内域名走国内 DNS（223.5.5.5，经有线），境外域名走学校 DNS（经 WiFi）

### WiFi 保活

三层防护：

1. **根治**：关闭 USB WiFi 网卡的"允许系统关闭设备省电"（`MSPower_DeviceEnable`）
2. **根治**：无线网卡省电模式设为"最高性能"（交流 + 直流）
3. **保活**：每 15 秒检查 WiFi 连接，断开则 `netsh wlan connect` 自动重连；每 300 秒复查一次电源管理，防止换 USB 口后设置被重置

## 常用参数

```powershell
# 保活监控间隔改为 60 秒（默认 15）
.\wifi-keepalive.ps1 monitor -IntervalSec 60

# 电源修复复查间隔改为 120 秒（默认 300）
.\wifi-keepalive.ps1 install -FixIntervalSec 120

# 手动指定 WiFi 配置文件（默认自动探测）
.\wifi-keepalive.ps1 monitor -ProfileName "WKU-VPN"
```

## 多设备复用

整个文件夹拷到另一台 Windows 设备，重复「安装步骤」即可。所有网卡名、子网、WiFi 配置文件、DNS 都是**运行时自动探测**，无需改任何代码。

## 常见问题

### 1. 境外网站打不开

**先查 WiFi 是否断开**（最常见原因）：

```powershell
Get-NetAdapter -Name WLAN | Select-Object Status
```

若 `Disconnected`，手动连接：`netsh wlan connect name="WKU-VPN"`。保活模块应在 15 秒内自动重连。

### 2. 运行脚本报"意外的标记/字符串缺少终止符"

这是 Windows PowerShell 5.1 的编码问题——脚本必须用 **UTF-8 带 BOM** 保存。本项目脚本已按此保存。如果从别处复制修改过脚本导致报错，用以下命令重新转码：

```powershell
$p = "<脚本路径>"
$c = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText($p, $c, (New-Object System.Text.UTF8Encoding($true)))
```

### 3. 换 USB 口后 WiFi 又断

USB WiFi 的电源管理设置是**按设备实例（绑定物理端口）**存储的，换口会生成新实例、设置重置。保活循环每 300 秒复查一次，会自动重新修复；或手动跑一次 `.\wifi-keepalive.ps1 fix`。

### 4. 板载 WiFi 网卡会受影响吗

板载 PCIe/M.2 WiFi 通常不会因"允许关闭设备省电"断连（那是 USB 网卡通病）。若板载 WiFi 也断，检查 BIOS 里的「LAN/WLAN 自动切换」选项，以及 `fMinimizeConnections` 策略。

## 关于上传 GitHub

第三方二进制已在 `.gitignore` 中排除（见上「第三方依赖」章节），无需额外处理。只需确保不手动 `git add -f` 这些文件即可。

## 许可证

本项目脚本为自用工具，可自由分发。依赖的第三方组件遵循各自许可证（见「第三方依赖」章节）。
