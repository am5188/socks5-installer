#!/bin/bash

echo "======================================================="
echo "   币安 (Binance) API 高频交易网络基准测试工具 v2.0   "
echo "   Financial Network Benchmark for HFT (SOCKS5/Direct) "
echo "======================================================="
echo "检查时间: $(date)"

# -------------------------------------------------
# 0. 环境准备与依赖安装
# -------------------------------------------------
echo ""
echo "[0] 环境检查与依赖安装..."
if ! command -v traceroute >/dev/null || ! command -v bc >/dev/null; then
    echo "    -> 正在安装必要的测试工具 (traceroute, bc)..."
    # Silent install
    apt-get update -qq >/dev/null
    apt-get install -y traceroute bc >/dev/null
fi
echo "    -> 环境就绪。"

# -------------------------------------------------
# 1. 配置提取
# -------------------------------------------------
PROXY_TEST_ENABLED=false
USER_FILE="/etc/socks5_users"
PASS_FILE="/etc/socks5_passwd"

if [ -f /etc/danted.conf ] && [ -s "$USER_FILE" ] && [ -s "$PASS_FILE" ]; then
    PORT=$(grep 'internal:' /etc/danted.conf | grep 'port =' | awk '{print $5}')
    TEST_USER=$(head -n 1 "$USER_FILE")
    TEST_PASS=$(grep "^$TEST_USER:" "$PASS_FILE" | cut -d: -f2)
    
    if [ -n "$PORT" ] && [ -n "$TEST_USER" ] && [ -n "$TEST_PASS" ]; then
        PROXY_TEST_ENABLED=true
        echo "    -> 检测到 SOCKS5 服务 (端口: $PORT)，将执行【直连 vs 代理】对比测试。"
    else
        echo "    -> SOCKS5 配置不完整，仅执行直连测试。"
    fi
else
    echo "    -> 未检测到 SOCKS5 服务，仅执行【服务器直连】基准测试。"
fi

API_HOST="api.binance.com"
URL_TIME="https://api.binance.com/api/v3/time"

# -------------------------------------------------
# 2. 延迟与抖动测试 (Ping Jitter)
# -------------------------------------------------
echo ""
echo ">>> [1/4] 延迟与抖动测试 (Latency & Jitter)"
echo "    目标: 发送 50 个 ICMP 包，评估网络物理链路的稳定性。"
echo "    标准: 高频交易要求 < 100ms 延迟，Jitter < 5ms，0% 丢包。"

echo -n "    -> 正在 Ping $API_HOST (50 packets)... "
PING_DATA=$(ping -c 50 -i 0.1 -q $API_HOST 2>&1)

# Extract data
LOSS=$(echo "$PING_DATA" | grep -o "[0-9]*% packet loss" | awk '{print $1}' | tr -d '%')
STATS=$(echo "$PING_DATA" | tail -1 | awk -F '/' '{print $4 "/" $5 "/" $6 "/" $7}')
MIN=$(echo "$STATS" | awk -F '/' '{print $1}')
AVG=$(echo "$STATS" | awk -F '/' '{print $2}')
MAX=$(echo "$STATS" | awk -F '/' '{print $3}')
MDEV=$(echo "$STATS" | awk -F '/' '{print $4}' | awk '{print $1}') # Jitter

if [ -z "$AVG" ]; then
    echo "FAIL (Ping 无法连通)"
    AVG=9999
    MDEV=9999
    LOSS=100
else
    echo "完成"
    echo "    -------------------------------------------"
    echo "    丢包率 (Loss)   : ${LOSS}%  (0% 为完美)"
    echo "    平均延迟 (Avg)  : ${AVG} ms"
    echo "    网络抖动 (Jitter): ${MDEV} ms (越小越稳)"
    echo "    延迟范围        : ${MIN} ms - ${MAX} ms"
    echo "    -------------------------------------------"
fi

# -------------------------------------------------
# 3. 路由追踪 (Traceroute)
# -------------------------------------------------
echo ""
echo ">>> [2/4] 路由路径分析 (Traceroute)"
echo "    目标: 检测到币安服务器的跳数 (Hops)。跳数越少，被干扰概率越低。"
echo -n "    -> 正在追踪路由... "
# Run traceroute, get last hop number
TRACE_RES=$(traceroute -n -w 1 -q 1 $API_HOST 2>&1)
HOPS=$(echo "$TRACE_RES" | tail -1 | awk '{print $1}')
echo "完成 (共 $HOPS 跳)"
# Print last 3 hops for privacy but info
echo "    关键路径节点 (最后 3 跳):"
echo "$TRACE_RES" | tail -3 | sed 's/^/    /'

# -------------------------------------------------
# 4. 并发 HTTP 连接稳定性测试 (Concurrency)
# -------------------------------------------------
echo ""
echo ">>> [3/4] 高频并发请求测试 (HTTP Concurrency)"
echo "    目标: 模拟 20 次连续 API 请求，统计成功率和 HTTP 握手耗时。"

run_http_test() {
    local use_proxy=$1
    local proxy_url=$2
    local total_req=20
    local success=0
    local fail=0
    local total_time=0
    local min_time=9999
    local max_time=0
    
    echo "    -> 开始测试 (模式: $([ "$use_proxy" == "true" ] && echo "代理转发" || echo "直连")) ..."
    
    for ((i=1; i<=total_req; i++)); do
        # Format: http_code:time_total
        if [ "$use_proxy" == "true" ]; then
            RES=$(curl -s -w "% {http_code}:%{time_total}" -o /dev/null -m 3 --proxy "$proxy_url" "$URL_TIME")
        else
            RES=$(curl -s -w "% {http_code}:%{time_total}" -o /dev/null -m 3 "$URL_TIME")
        fi
        
        CODE=$(echo "$RES" | cut -d: -f1)
        TIME=$(echo "$RES" | cut -d: -f2)
        
        if [ "$CODE" == "200" ]; then
            ((success++))
            # BC for float comparison
            if (( $(echo "$TIME < $min_time" | bc -l) )); then min_time=$TIME; fi
            if (( $(echo "$TIME > $max_time" | bc -l) )); then max_time=$TIME; fi
            total_time=$(echo "$total_time + $TIME" | bc -l)
        else
            ((fail++))
        fi
        # Progress bar
        echo -n "."
    done
    echo " 完成"
    
    if [ "$success" -gt 0 ]; then
        avg_time=$(echo "$total_time / $success * 1000" | bc -l) # Convert to ms
        min_time_ms=$(echo "$min_time * 1000" | bc -l)
        max_time_ms=$(echo "$max_time * 1000" | bc -l)
        
        printf "    成功率: %d/%d (%.0f%%)\n" "$success" "$total_req" "$((success * 100 / total_req))"
        printf "    HTTP耗时: 平均 %.2f ms | 最小 %.2f ms | 最大 %.2f ms\n" "$avg_time" "$min_time_ms" "$max_time_ms"
        
        # Return avg for comparison
        echo "$avg_time"
    else
        echo "    所有请求均失败！"
        echo "9999"
    fi
}

echo "    [3.1] 直连并发测试:"
AVG_DIRECT=$(run_http_test "false" "")

AVG_PROXY=0
if [ "$PROXY_TEST_ENABLED" = "true" ]; then
    echo ""
    echo "    [3.2] SOCKS5 代理并发测试:"
    PROXY_URL="socks5h://$TEST_USER:$TEST_PASS@127.0.0.1:$PORT"
    AVG_PROXY=$(run_http_test "true" "$PROXY_URL")
fi

# -------------------------------------------------
# 5. 综合评估报告
# -------------------------------------------------
echo ""
echo ">>> [4/4] 综合评估报告 (Report)"
echo "======================================================="

# 1. Network Stability
if (( $(echo "$LOSS > 0" | bc -l) )); then
    echo "🔴 网络质量: 差 (存在丢包 $LOSS%)"
    echo "   -> 极度不建议用于高频交易，丢包会导致订单严重滞后。"
elif (( $(echo "$MDEV > 10" | bc -l) )); then
    echo "🟡 网络质量: 一般 (抖动较高 ${MDEV}ms)"
    echo "   -> 价格波动剧烈时可能会卡顿。"
else
    echo "🟢 网络质量: 优秀 (无丢包，低抖动)"
fi

# 2. Latency
if (( $(echo "$AVG > 200" | bc -l) )); then
    echo "🔴 物理延迟: 高 (${AVG}ms) - 服务器距离交易所过远。"
elif (( $(echo "$AVG > 100" | bc -l) )); then
    echo "🟡 物理延迟: 中 (${AVG}ms) - 适合趋势交易，不适合超高频。"
else
    echo "🟢 物理延迟: 低 (${AVG}ms) - 极佳的物理位置。"
fi

# 3. Proxy Overhead
if [ "$PROXY_TEST_ENABLED" = "true" ] && [ "$AVG_PROXY" != "9999" ]; then
    OVERHEAD=$(echo "$AVG_PROXY - $AVG_DIRECT" | bc -l)
    echo "ℹ️  代理损耗: 约 $(printf "%.2f" $OVERHEAD) ms (HTTP层面)"
    
    if (( $(echo "$OVERHEAD > 50" | bc -l) )); then
        echo "🟡 代理性能: 损耗较高。可能是 CPU 负载高或加密开销。"
    else
        echo "🟢 代理性能: 损耗极低。SOCKS5 服务运行高效。"
    fi
    
    echo "✅ 最终结论: 本服务器已安装代理且功能正常。"
else
    if [ "$PROXY_TEST_ENABLED" = "false" ]; then
        echo "ℹ️  代理状态: 未安装或未运行。"
        echo "✅ 最终结论: 服务器网络底子不错，建议安装 SOCKS5 服务。"
    else
        echo "🔴 代理状态: 已安装但测试失败 (无法连接)。"
    fi
fi
echo "======================================================="
