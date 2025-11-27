# SOCKS5 自动安装器 & 管理工具

此脚本用于在 Ubuntu 系统上自动安装和配置 SOCKS5 代理服务器 (dante-server)，并提供一个便捷的命令行工具 `am` 用于后续管理。

## ✨ 功能特点

*   🚀 **一键安装**：自动处理依赖、配置、防火墙和开机自启。
*   🛠 **管理面板**：安装后内置 `am` 命令，方便进行日常维护。
*   👥 **多用户支持**：轻松添加、删除和修改 SOCKS5 账号。
*   📱 **二维码 & 链接生成**：直接显示 SOCKS5/SOCKS5h 链接及终端二维码，方便扫码连接。
*   🔍 **币安网络专测**：提供专业的网络诊断脚本，全面检测服务器直连与代理转发到币安 API 的延迟、丢包与稳定性 (MTU 检测)。
*   🗑 **一键卸载**：支持完全清理环境，不留残留。

## 📦 安装方法

### 方式一：交互式安装 (推荐)

直接复制以下命令到终端运行，脚本会引导您输入配置信息（用户名、密码、端口）：

#### 使用 `wget`
```bash
wget -O - https://raw.githubusercontent.com/am5188/socks5-installer/main/install_socks5.sh | bash
```

#### 使用 `curl`
```bash
curl -fsSL https://raw.githubusercontent.com/am5188/socks5-installer/main/install_socks5.sh | bash
```

### 方式二：静默安装 (自定义参数)

如果您需要自动化部署，可以直接在命令行中指定参数：

#### 使用 `wget`
```bash
# 用法: ... | bash -s -- <用户名> <密码> <端口>
wget -O - https://raw.githubusercontent.com/am5188/socks5-installer/main/install_socks5.sh | bash -s -- myuser mypassword123 1080
```

#### 使用 `curl`
```bash
# 用法: ... | bash -s -- <用户名> <密码> <端口>
curl -fsSL https://raw.githubusercontent.com/am5188/socks5-installer/main/install_socks5.sh | bash -s -- myuser mypassword123 1080
```

## 🎮 管理命令 (am)

安装完成后，您可以在终端任何位置输入 `am` 来打开管理面板。

```bash
root@server:~# am
```

**管理菜单功能：**

1.  **添加用户 (Add User)**：创建新的 SOCKS5 认证账号。
2.  **删除用户 (Delete User)**：移除现有的账号。
3.  **修改密码 (Change Pass)**：重置指定用户的密码。
4.  **用户列表 (List Users)**：查看当前所有已创建的用户。
5.  **运行状态 (Check Status)**：查看服务运行状态、监听端口和公网 IP。
6.  **查看配置信息 (View Config)**：选择用户并显示详细连接信息（含 **明文密码**、**SOCKS5 链接**、**二维码**）。
7.  **卸载程序 (Uninstall)**：停止服务并彻底删除程序及相关配置。

## 🩺 网络诊断工具 (check_socks5.sh)

如果遇到连接问题，或需要测试币安 API 的连通性，可以使用此脚本进行全面体检。它会对比“直连”与“代理转发”的延迟、丢包率及大包传输稳定性，精准定位 MTU 问题或 IP 屏蔽。

```bash
curl -fsSL https://raw.githubusercontent.com/am5188/socks5-installer/main/check_socks5.sh | bash
```

## 📁 文件说明

*   `install_socks5.sh`: 核心安装脚本。
*   `/etc/danted.conf`: dante-server 配置文件。
*   `/usr/local/bin/am`: 管理命令脚本。
*   `/etc/socks5_users`: 用户名列表记录文件。
*   `/etc/socks5_passwd`: 密码记录文件 (权限 600，仅 root 可读)。
*   `check_socks5.sh`: 币安 API 网络稳定性全面诊断脚本。

## ⚠️ 注意事项

*   **云服务器安全组/防火墙**: 如果您在云服务商 (如腾讯云) 上部署，请务必在控制台的安全组或防火墙中开放 SOCKS5 端口 (默认为 1080 或您设置的端口，例如 5188) 的 TCP 流量。
*   **远程 DNS**: 客户端软件连接 SOCKS5 代理时，请确保开启了“远程 DNS”或“代理端解析域名”功能 (对应 `socks5h` 模式)，以避免 DNS 污染。
*   **MTU 问题**: 如果诊断脚本提示大包传输失败，请尝试降低网卡 MTU (例如 `ip link set dev eth0 mtu 1350`)。
