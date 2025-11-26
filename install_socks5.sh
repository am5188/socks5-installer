#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
  echo "请使用 root 权限运行此脚本"
  exit 1
fi

# Get arguments or prompt
USER=${1}
PASS=${2}
PORT=${3:-1080}

if [ -z "$USER" ]; then
    read -p "请输入 SOCKS5 用户名: " USER
fi

if [ -z "$PASS" ]; then
    read -s -p "请输入 SOCKS5 密码: " PASS
    echo ""
fi

if [ -z "$PORT" ]; then
    read -p "请输入 SOCKS5 端口 (默认 1080): " PORT
    PORT=${PORT:-1080}
fi

echo "正在安装 SOCKS5 服务器，配置如下:"
echo "用户: $USER"
echo "端口: $PORT"

# Update and install dante-server
apt-get update
apt-get install -y dante-server

# Detect network interface
INTERFACE=$(ip route get 1.1.1.1 | awk '{print $5; exit}')
if [ -z "$INTERFACE" ]; then
    INTERFACE="eth0"
fi
echo "检测到的网络接口: $INTERFACE"

# Configure dante-server
mv /etc/danted.conf /etc/danted.conf.bak
cat > /etc/danted.conf <<EOF
logoutput: syslog
user.privileged: root
user.unprivileged: nobody

# The listening network interface or address.
internal: 0.0.0.0 port = $PORT

# The proxying network interface or address.
external: $INTERFACE

# socks-rules determine what is proxied through the external interface.
socksmethod: username

# client-rules determine who can connect to the internal interface.
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error connect disconnect
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error connect disconnect
}
EOF

# Create user if not exists, or update password
if id "$USER" &>/dev/null; then
    echo "用户 $USER 已存在，正在更新密码..."
else
    echo "正在创建用户 $USER..."
    useradd -r -s /bin/false $USER
fi
echo "$USER:$PASS" | chpasswd

# Allow port in ufw if active
if ufw status | grep -q "Status: active"; then
    ufw allow $PORT/tcp
    echo "已在 UFW 防火墙中开放端口 $PORT。"
fi

# Restart service
systemctl restart danted
systemctl enable danted

# Check status
if systemctl is-active --quiet danted; then
    echo "=========================================="
    echo "SOCKS5 服务器已安装并成功运行！"
    echo "地址: $(curl -s ifconfig.me):$PORT"
    echo "用户:    $USER"
    echo "密码:    ******"
    echo "=========================================="
else
    echo "错误: dante-server 启动失败。"
    systemctl status danted
fi
