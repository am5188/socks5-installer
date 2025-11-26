# SOCKS5 自动安装器

此脚本用于在 Ubuntu 系统上自动安装和配置 SOCKS5 代理服务器 (dante-server)。

## 使用方法

### 一键安装 (推荐)

您可以直接在 Ubuntu 服务器上运行以下命令进行安装。脚本将提示您输入用户名、密码和端口。

```bash
wget -O - https://raw.githubusercontent.com/am5188/socks5-installer/main/install_socks5.sh | bash
```

### 完全一键命令 (自定义账号密码)

如果您想在命令行中直接指定用户名、密码和端口，可以使用以下命令：

```bash
# 用法: ... | bash -s -- <用户名> <密码> <端口>
wget -O - https://raw.githubusercontent.com/am5188/socks5-installer/main/install_socks5.sh | bash -s -- myuser mypassword123 1080
```

### 手动使用

1.  克隆此仓库：
    ```bash
    git clone https://github.com/am5188/socks5-installer.git
    cd socks5-installer
    ```
2.  使脚本可执行：
    ```bash
    chmod +x install_socks5.sh
    ```
3.  运行脚本：
    ```bash
    ./install_socks5.sh [用户名] [密码] [端口]
    ```

## 文件说明

*   `install_socks5.sh`: SOCKS5 服务器安装脚本，负责 `dante-server` 的安装、配置、防火墙设置和用户管理。
*   `README.md`: 本使用说明文档。