# SOCKS5 自动安装器 & 管理工具

此项目提供了一个完整的解决方案，用于在 Ubuntu 系统上快速部署和管理 SOCKS5 代理服务器，并集成了强大的网络诊断工具，特别针对币安 API 通信进行了优化。

## ✨ 主要功能与优势

*   🚀 **服务器一键部署**：全自动安装、配置 SOCKS5 代理服务 (dante-server)，处理依赖、防火墙和开机自启。
*   🛠 **服务器管理面板 (am 命令)**：安装后提供交互式命令行工具，方便日常维护。
*   👥 **多用户支持**：轻松进行 SOCKS5 账号的添加、删除、修改密码和列表查看。
*   📱 **便捷连接信息**：直接生成 SOCKS5/SOCKS5h 链接及终端二维码，方便客户端快速配置。
*   🩺 **服务器网络诊断 (check_socks5.sh)**：专业级的网络基准测试工具，全面评估服务器直连与代理转发到币安 API 的网络质量（延迟、抖动、丢包、MTU）。
*   📈 **本地性能基准测试 (bnb-test)**：在本地客户端安装交互式工具，测试本地到币安 API 的直连和通过指定 SOCKS5 代理的连接性能，并提供智能诊断和建议。
*   🗑 **一键卸载**：服务器端和本地工具均支持彻底清理，不留残留。

## 📦 安装方法 (服务器端)

### 方式一：交互式安装 (推荐)

直接复制以下命令到 Ubuntu 服务器终端运行，脚本将引导您输入配置信息（用户名、密码、端口）：

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

## 🎮 服务器管理命令 (am)

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

## 🩺 服务器网络诊断工具 (check_socks5.sh)

在服务器上，如果遇到连接问题，或需要测试币安 API 的连通性，可以使用此脚本进行全面体检。它会对比“直连”与“代理转发”的延迟、丢包率及大包传输稳定性，精准定位 MTU 问题或 IP 屏蔽。

```bash
curl -fsSL https://raw.githubusercontent.com/am5188/socks5-installer/main/check_socks5.sh | bash
```

## 💻 本地客户端工具 (bnb-test)

此工具用于在您的 **本地电脑 (macOS, Linux, Windows Git Bash)** 上测试本地到币安 API 的连接质量。它支持直连测试和通过指定 SOCKS5 代理的测试，并提供详细诊断。

### 安装本地工具

在您的本地电脑终端运行以下命令进行安装。安装后，`bnb-test` 命令将被添加到您的系统路径中。

```bash
curl -fsSL https://raw.githubusercontent.com/am5188/socks5-installer/main/install_local_tool.sh | bash
```

### 使用本地工具

安装成功后，在本地终端输入 `bnb-test` 即可启动交互式菜单：

```bash
bnb-test
```

**菜单选项：**
1.  **使用本机直连测试 (Direct)**：测试您的本地电脑直接访问币安 API 的网络性能。
2.  **使用 SOCKS5 代理测试 (Proxy)**：测试通过指定的 SOCKS5 代理访问币安 API 的网络性能。
3.  **卸载此工具 (Uninstall)**：从您的本地电脑中删除 `bnb-test` 命令及相关配置。
4.  **退出 (Exit)**：退出工具。

## 📁 文件说明

*   `install_socks5.sh`: 服务器核心安装脚本。
*   `/etc/danted.conf`: dante-server 配置文件 (服务器)。
*   `/usr/local/bin/am`: 服务器管理命令脚本。
*   `/etc/socks5_users`: 服务器 SOCKS5 用户名列表记录文件。
*   `/etc/socks5_passwd`: 服务器 SOCKS5 密码记录文件 (权限 600，仅 root 可读)。
*   `check_socks5.sh`: 服务器端币安 API 网络稳定性全面诊断脚本。
*   `install_local_tool.sh`: 本地客户端工具安装器。
*   `/usr/local/bin/bnb-test` (或 `$HOME/bnb-test` on Windows): 本地客户端工具脚本。
*   `~/.bnb_test_config`: 本地客户端工具保存的代理配置。

## ⚠️ 注意事项

*   **云服务器安全组/防火墙**: 如果您在云服务商 (如腾讯云) 上部署，请务必在控制台的安全组或防火墙中开放 SOCKS5 端口 (默认为 1080 或您设置的端口，例如 5188) 的 TCP 流量。
*   **远程 DNS**: 客户端软件连接 SOCKS5 代理时，请确保开启了“远程 DNS”或“代理端解析域名”功能 (对应 `socks5h` 模式)，以避免 DNS 污染。
*   **SOCKS5 协议特性**: SOCKS5 代理本身是明文协议，在经过严格审查的网络环境下 (如 GFW) 容易被识别和阻断，导致连接超时或重置。如果本地测试代理失败，请考虑使用 SSH 隧道或 Shadowsocks 等加密代理方案。