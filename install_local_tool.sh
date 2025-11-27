#!/bin/bash

echo "=== 币安 API 本地基准测试工具安装器 ==="

# Detect OS
OS_TYPE="unknown"
case "$OSTYPE" in
  solaris*) OS_TYPE="linux" ;; 
  darwin*)  OS_TYPE="mac" ;; 
  linux*)   OS_TYPE="linux" ;;
  bsd*)     OS_TYPE="bsd" ;;
  msys*)    OS_TYPE="windows" ;;
  cygwin*)  OS_TYPE="windows" ;;
  *)        OS_TYPE="linux" ;;
esac

echo "检测到系统: $OS_TYPE"

INSTALL_DIR="/usr/local/bin"
CMD_NAME="bnb-test"
# Use a random query param to bypass cache
DOWNLOAD_URL="https://raw.githubusercontent.com/am5188/socks5-installer/main/bnb_test.sh?v=$(date +%s)"

# Check root for install if not windows
if [ "$OS_TYPE" != "windows" ] && [ "$EUID" -ne 0 ]; then
    SUDO="sudo"
else
    SUDO=""
fi

echo "正在下载最新版工具..."
# Download to temp file first
curl -fsSL "$DOWNLOAD_URL" -o ./bnb-test-temp

if [ ! -s ./bnb-test-temp ]; then
    echo "❌ 下载失败。请检查网络连接。"
    exit 1
fi

chmod +x ./bnb-test-temp

if [ "$OS_TYPE" == "windows" ]; then
    echo "Windows 环境 (Git Bash): 将脚本移动到当前用户目录..."
    mv ./bnb-test-temp "$HOME/$CMD_NAME"
    echo "✅ 安装完成！"
    echo "您可以直接运行: ~/$CMD_NAME"
else
    echo "正在安装到 $INSTALL_DIR ..."
    
    # Remove old version if exists
    if [ -f "$INSTALL_DIR/$CMD_NAME" ]; then
        echo "覆盖旧版本..."
        $SUDO rm -f "$INSTALL_DIR/$CMD_NAME"
    fi
    
    $SUDO mv ./bnb-test-temp "$INSTALL_DIR/$CMD_NAME"
    
    if [ $? -eq 0 ]; then
        echo "✅ 安装成功！"
        echo "您现在可以在终端任何地方输入 '$CMD_NAME' 来启动测试。"
    else
        echo "❌ 安装失败。移动文件时出错，请检查权限。"
        rm ./bnb-test-temp
    fi
fi