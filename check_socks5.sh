#!/bin/bash

echo "=== 币安 (Binance) API 网络稳定性全面检查工具 ==="
echo "检查时间: $(date)"

# -------------------------------------------------
# 0. 配置提取
# -------------------------------------------------
if [ ! -f /etc/danted.conf ]; then
    echo "错误: 未找到 /etc/danted.conf"
    exit 1
fi

# Extract port (robust logic)
PORT=$(grep 'internal:' /etc/danted.conf | grep 'port =' | awk '{print $5}')
USER_FILE="/etc/socks5_users"
PASS_FILE="/etc/socks5_passwd"

if [ ! -s "$USER_FILE" ] || [ ! -s "$PASS_FILE" ]; then
    echo "错误: 未找到用户配置文件，无法进行代理测试。"
    exit 1
fi

# Use the first user for testing
TEST_USER=$(head -n 1 "$USER_FILE")
TEST_PASS=$(grep "^$TEST_USER:" "$PASS_FILE" | cut -d: -f2)

if [ -z "$PORT" ] || [ -z "$TEST_USER" ] || [ -z "$TEST_PASS" ]; then
    echo "错误: 配置提取失败 (PORT=$PORT, USER=$TEST_USER)。"
    exit 1
fi

API_HOST="api.binance.com"
URL_SMALL="https://api.binance.com/api/v3/time"
URL_LARGE="https://api.binance.com/api/v3/exchangeInfo"

echo "测试配置: 本地端口 $PORT | 测试用户 $TEST_USER"
echo "-------------------------------------------------"

# -------------------------------------------------
# 1. 服务器直连测试
# -------------------------------------------------
echo ""
echo ">>> [1/3] 服务器直连测试 (Direct Connection)"
echo "    目标: 验证服务器本身是否能访问币安，排除云厂商屏蔽。"

# DNS & Ping
echo -n "  - [DNS/Ping] 解析与延迟: "
PING_RES=$(ping -c 4 -i 0.2 -W 2 $API_HOST 2>&1)
if [ $? -eq 0 ]; then
    # Attempt to extract packet loss and RTT, fallback if format differs
    LOSS=$(echo "$PING_RES" | grep -o "[0-9]*% packet loss" | awk '{print $1}')
    AVG_RTT=$(echo "$PING_RES" | tail -1 | awk -F '/' '{print $5}')
    echo "OK (丢包率: $LOSS, 平均延迟: ${AVG_RTT}ms)"
else
    echo "FAIL (Ping 失败，可能禁止 Ping 或 DNS 解析错误)"
fi

# HTTP Small
echo -n "  - [HTTP小包] 基础连接 (/api/v3/time): "
START=$(date +%s%N)
# Use python for simpler math if date +%s%N is not precise or available? No, date is standard on ubuntu.
# Handle cases where %N is not supported (some basic sh)
if date +%s%N | grep -q "N"; then
   # Fallback for systems without nanoseconds
   START=$(date +%s)
   HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "$URL_SMALL")
   END=$(date +%s)
   DUR=$(( ($END - $START) * 1000 ))
else
   HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "$URL_SMALL")
   END=$(date +%s%N)
   DUR=$(( ($END - $START) / 1000000 ))
fi

if [ "$HTTP_CODE" == "200" ]; then
    echo "OK (HTTP 200, 耗时: ${DUR}ms)"
else
    echo "FAIL (HTTP $HTTP_CODE)"
fi

# HTTP Large
echo -n "  - [HTTP大包] MTU/TLS稳定性 (/api/v3/exchangeInfo): "
HTTP_CODE_L=$(curl -s -o /dev/null -w "%{http_code}" -m 15 "$URL_LARGE")
if [ "$HTTP_CODE_L" == "200" ]; then
    echo "OK (传输稳定)"
else
    echo "FAIL (传输失败 HTTP $HTTP_CODE_L，可能存在 MTU 问题)"
fi


# -------------------------------------------------
# 2. SOCKS5 代理转发测试
# -------------------------------------------------
echo ""
echo ">>> [2/3] SOCKS5 代理转发测试 (Via Localhost)"
echo "    目标: 验证 danted 服务是否能正确转发流量到币安。"

PROXY="socks5h://$TEST_USER:$TEST_PASS@127.0.0.1:$PORT"

# Proxy Small
echo -n "  - [代理小包] 基础转发 (/api/v3/time): "
# Reset timer logic
if date +%s%N | grep -q "N"; then
   START=$(date +%s)
   P_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 10 --proxy "$PROXY" "$URL_SMALL")
   END=$(date +%s)
   P_DUR=$(( ($END - $START) * 1000 ))
else
   START=$(date +%s%N)
   P_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 10 --proxy "$PROXY" "$URL_SMALL")
   END=$(date +%s%N)
   P_DUR=$(( ($END - $START) / 1000000 ))
fi

if [ "$P_HTTP_CODE" == "200" ]; then
    echo "OK (HTTP 200, 耗时: ${P_DUR}ms)"
else
    echo "FAIL (HTTP $P_HTTP_CODE)"
    echo "    -> 调试信息:"
    curl -v -m 5 --proxy "$PROXY" "$URL_SMALL" 2>&1 | head -n 5 | sed 's/^/       /'
fi

# Proxy Large
echo -n "  - [代理大包] 稳定性测试 (/api/v3/exchangeInfo): "
P_HTTP_CODE_L=$(curl -s -o /dev/null -w "%{http_code}" -m 20 --proxy "$PROXY" "$URL_LARGE")

if [ "$P_HTTP_CODE_L" == "200" ]; then
    echo "OK (转发稳定)"
else
    echo "FAIL (HTTP $P_HTTP_CODE_L)"
    echo "    -> 警告: 如果直连大包成功但代理失败，通常是 MTU 问题。"
    echo "    -> 建议: 尝试 'ip link set dev eth0 mtu 1350' 后重试。"
fi

# -------------------------------------------------
# 3. 诊断总结
# -------------------------------------------------
echo ""
echo ">>> [3/3] 诊断总结"
if [ "$HTTP_CODE" != "200" ]; then
    echo "🔴 严重: 服务器直连币安失败。可能是腾讯云/阿里云屏蔽了币安，代理无法解决此问题。"
elif [ "$P_HTTP_CODE" != "200" ]; then
    echo "🔴 严重: 直连正常，但代理转发失败。请检查 danted 服务状态或防火墙端口阻断。"
elif [ "$P_HTTP_CODE_L" != "200" ]; then
    echo "🟡 警告: 基础连接正常，但大包传输失败。极大概率是 MTU 问题。请降低网卡 MTU。"
else
    echo "🟢 完美: 您的 SOCKS5 代理与币安 API 连接非常稳定！"
fi
echo "================================================="