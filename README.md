# SOCKS5 自动安装器 & 管理工具

此脚本用于在 Ubuntu 系统上自动安装和配置 SOCKS5 代理服务器 (dante-server)，并提供一个便捷的命令行工具 `am` 用于后续管理。

## ✨ 功能特点

*   🚀 **一键安装**：自动处理依赖、配置、防火墙和开机自启。
*   🛠 **管理面板**：安装后内置 `am` 命令，方便进行日常维护。
*   👥 **多用户支持**：轻松添加、删除和修改 SOCKS5 账号。
*   🗑 **一键卸载**：支持完全清理环境，不留残留。

## 📦 安装方法

### 方式一：交互式安装 (推荐)

直接复制以下命令到终端运行，脚本会引导您输入配置信息：

```bash
wget -O - https://raw.githubusercontent.com/am5188/socks5-installer/main/install_socks5.sh | bash
```

### 方式二：静默安装 (自定义参数)

如果您需要自动化部署，可以直接在命令行中指定参数：

```bash
# 用法: ... | bash -s -- <用户名> <密码> <端口>
wget -O - https://raw.githubusercontent.com/am5188/socks5-installer/main/install_socks5.sh | bash -s -- myuser mypassword123 1080
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
6.  **卸载程序 (Uninstall)**：停止服务并彻底删除程序及相关配置。

## 📁 文件说明

*   `install_socks5.sh`: 核心安装脚本。
*   `/etc/danted.conf`: dante-server 配置文件。
*   `/usr/local/bin/am`: 管理命令脚本。
*   `/etc/socks5_users`: 用户列表记录文件。
