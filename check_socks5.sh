#!/bin/bash

echo "=== 币安 (Binance) API 网络稳定性全面检查工具 ==="
echo "检查时间: $(date)"

# -------------------------------------------------
# 0. 配置提取 (兼容模式)
# -------------------------------------------------
PROXY_TEST_ENABLED=false
USER_FILE="/etc/socks5_users"
PASS_FILE="/etc/socks5_passwd"

if [ -f /etc/danted.conf ] && [ -s "$USER_FILE" ] && [ -s "$PASS_FILE" ]; then
    # Extract port
    PORT=$(grep 'internal:' /etc/danted.conf | grep 'port =' | awk '{print $5}')
    # Extract user/pass
    TEST_USER=$(head -n 1 "$USER_FILE")
    TEST_PASS=$(grep "^$TEST_USER:" "$PASS_FILE" | cut -d: -f2)
    
    if [ -n "$PORT" ] && [ -n "$TEST_USER" ] && [ -n "$TEST_PASS" ]; then
        PROXY_TEST_ENABLED=true
        echo "检测到 SOCKS5 服务，将执行完整测试 (直连 + 代理)。"
        echo "测试配置: 本地端口 $PORT | 测试用户 $TEST_USER"
    else
        echo "警告: SOCKS5 配置文件存在但解析失败，将仅执行直连测试。"
    fi
else
    echo "提示: 未检测到 SOCKS5 服务安装，将仅执行服务器直连测试。"
fi
echo "-------------------------------------------------"

API_HOST="api.binance.com"
URL_SMALL="https://api.binance.com/api/v3/time"
URL_LARGE="https://api.binance.com/api/v3/exchangeInfo"

# -------------------------------------------------
# 1. 服务器直连测试
# -------------------------------------------------
echo ""
echo ">>> [1/2] 服务器直连测试 (Direct Connection)"
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
START=$(date +%s%N 2>/dev/null)
if [ -z "$START" ]; then START=$(date +%s); fi # Fallback

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "$URL_SMALL")

END=$(date +%s%N 2>/dev/null)
if [ -z "$END" ]; then END=$(date +%s); fi

# Calculate duration roughly (if date +%s%N supported, use ms, else just second diff * 1000 which is 0 or 1000...)
# To be safe across ubuntu versions:
if [[ "$START" -gt 10000000000 ]]; then # heuristic for nanoseconds
    DUR=$(( ($END - $START) / 1000000 ))
else
    DUR=$(( ($END - $START) * 1000 ))
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
# 2. SOCKS5 代理转发测试 (仅当服务存在时)
# -------------------------------------------------
if [ "$PROXY_TEST_ENABLED" = "true" ]; then
    echo ""
    echo ">>> [2/2] SOCKS5 代理转发测试 (Via Localhost)"
    echo "    目标: 验证 danted 服务是否能正确转发流量到币安。"

    PROXY="socks5h://$TEST_USER:$TEST_PASS@127.0.0.1:$PORT"

    # Proxy Small
    echo -n "  - [代理小包] 基础转发 (/api/v3/time): "
    
    START=$(date +%s%N 2>/dev/null)
    if [ -z "$START" ]; then START=$(date +%s); fi

    P_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 10 --proxy "$PROXY" "$URL_SMALL")

    END=$(date +%s%N 2>/dev/null)
    if [ -z "$END" ]; then END=$(date +%s); fi

    if [[ "$START" -gt 10000000000 ]]; then
        P_DUR=$(( ($END - $START) / 1000000 ))
    else
        P_DUR=$(( ($END - $START) * 1000 ))
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
fi

# -------------------------------------------------
# 3. 诊断总结
# -------------------------------------------------
echo ""
echo ">>> [总结]"
if [ "$HTTP_CODE" != "200" ]; then
    echo "🔴 严重: 服务器直连币安失败。"
    echo "    原因: 腾讯云/阿里云可能屏蔽了币安 IP，或者 DNS 解析被污染。"
    echo "    建议: 更换海外其他区域的服务器 (如新加坡、日本)。"
elif [ "$HTTP_CODE_L" != "200" ]; then
    echo "🟡 警告: 直连小包通，但大包挂了。"
    echo "    建议: 检查网络 MTU 设置，尝试 ip link set dev eth0 mtu 1350"
else
    if [ "$PROXY_TEST_ENABLED" = "false" ]; then
        echo "🟢 通过: 此服务器可以正常访问币安 API！"
        echo "    建议: 您可以放心地安装 SOCKS5 服务了。"
    else
        if [ "$P_HTTP_CODE" != "200" ]; then
            echo "🔴 严重: 直连正常，但代理转发失败。请检查 danted 服务状态。"
        elif [ "$P_HTTP_CODE_L" != "200" ]; then
            echo "🟡 警告: 代理大包传输失败，极大可能是 MTU 问题。请降低网卡 MTU。"
        else
            echo "🟢 完美: 您的 SOCKS5 代理与币安 API 连接非常稳定！"
        fi
    fi
fi
echo "================================================="