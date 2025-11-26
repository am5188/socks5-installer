#!/bin/bash

echo "=== SOCKS5 排查工具 ==="

# 1. Check Service
echo "[1] 检查服务状态..."
if systemctl is-active --quiet danted; then
    echo "SUCCESS: danted 服务正在运行。"
else
    echo "ERROR: danted 服务未运行！"
    systemctl status danted --no-pager
fi

# 2. Check Port
PORT=$(grep 'internal:' /etc/danted.conf | grep 'port =' | awk '{print $5}')
echo "[2] 检查监听端口 ($PORT)..."
if netstat -lnp | grep ":$PORT " >/dev/null; then
    echo "SUCCESS: 端口 $PORT 正在监听。"
else
    echo "ERROR: 端口 $PORT 未被监听！"
    netstat -lnp | grep danted
fi

# 3. Check Firewall (UFW)
echo "[3] 检查 UFW 防火墙..."
if command -v ufw >/dev/null; then
    if ufw status | grep -q "Status: active"; then
        if ufw status | grep -q "$PORT/tcp"; then
            echo "SUCCESS: UFW 已放行端口 $PORT。"
        else
            echo "WARNING: UFW 处于激活状态，但似乎未放行端口 $PORT！"
            echo "尝试修复: ufw allow $PORT/tcp"
        fi
    else
        echo "INFO: UFW 未激活 (Status: inactive)，防火墙可能由 iptables 或云安全组管理。"
    fi
else
    echo "INFO: 未安装 UFW。"
fi

# 4. Check Configuration
echo "[4] 检查配置文件..."
if [ -f /etc/danted.conf ]; then
    echo "配置文件存在。"
    # Simple check for syntax
    danted -V
else
    echo "ERROR: 配置文件 /etc/danted.conf 丢失！"
fi

# 5. Local Connectivity Test
echo "[5] 本地连接测试..."
USER_FILE="/etc/socks5_users"
PASS_FILE="/etc/socks5_passwd"
if [ -s "$USER_FILE" ] && [ -s "$PASS_FILE" ]; then
    TEST_USER=$(head -n 1 "$USER_FILE")
    TEST_PASS=$(grep "^$TEST_USER:" "$PASS_FILE" | cut -d: -f2)
    
    echo "正在使用用户 $TEST_USER 测试连接本地端口..."
    if command -v curl >/dev/null; then
        # Test connection to a public IP echo service via local socks proxy
        # We use -m 5 to timeout after 5 seconds
        RESPONSE=$(curl -s -m 5 --socks5-hostname "$TEST_USER:$TEST_PASS@127.0.0.1:$PORT" https://ifconfig.me 2>&1)
        if [[ "$RESPONSE" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
             echo "SUCCESS: 本地连接测试通过！SOCKS5 代理工作正常。"
        else
             echo "FAILURE: 本地连接测试失败。"
             echo "错误信息: $RESPONSE"
        fi
    else
        echo "WARNING: 未找到 curl，跳过连接测试。"
    fi
else
    echo "WARNING: 无法读取用户信息，跳过本地测试。"
fi

echo "==============================================="
echo "如果以上检查全部通过 (SUCCESS)，但外部仍无法连接："
echo "请务必检查 **云服务商控制台 (腾讯云/阿里云/AWS)** 的【安全组/防火墙】设置。"
echo "必须在安全组中放行 TCP 端口: $PORT"
echo "==============================================="
