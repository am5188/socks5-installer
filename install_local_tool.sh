#!/bin/bash

echo "=== 币安 API 本地基准测试工具安装器 ==="
echo "此脚本将在您的系统路径中安装 'bnb-test' 命令。"

# Detect OS
OS_TYPE="unknown"
case "$OSTYPE" in
  solaris*) OS_TYPE="linux" ;; # Treat as linux-like
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
CONFIG_FILE="$HOME/.bnb_test_config"

# Check root for install if not windows
if [ "$OS_TYPE" != "windows" ] && [ "$EUID" -ne 0 ]; then
    echo "提示: 安装到 /usr/local/bin 可能需要密码 (sudo)。"
    SUDO="sudo"
else
    SUDO=""
fi

# Create the script content
cat > ./bnb-test-temp <<EOF
#!/bin/bash

CONFIG_FILE="$HOME/.bnb_test_config"
DEFAULT_PROXY=""

# Load saved config
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

echo "======================================================="
echo "   Binance API Benchmark Tool (Local)"
echo "   [1] 直连测试 (Direct)"
echo "   [2] 代理测试 (SOCKS5 Proxy)"
echo "======================================================="

# Argument support
if [ -n "$1" ]; then
    PROXY_INPUT="$1"
    MODE="proxy"
else
    # Interactive
    if [ -n "$SAVED_PROXY" ]; then
        echo "检测到上次使用的代理: $SAVED_PROXY"
        read -p "是否使用此代理? [Y/n/new]: " CHOICE
        case "$CHOICE" in
            n|N) MODE="direct" ;; 
            new|NEW) 
                read -p "请输入新代理 (socks5h://...): " PROXY_INPUT
                MODE="proxy" 
                ;; 
            *) 
                PROXY_INPUT="$SAVED_PROXY"
                MODE="proxy" 
                ;; 
        esac
    else
        read -p "请输入代理地址 (回车跳过则进行直连测试): " PROXY_INPUT
        if [ -z "$PROXY_INPUT" ]; then
            MODE="direct"
        else
            MODE="proxy"
        fi
    fi
fi

# Save config if proxy used
if [ "$MODE" == "proxy" ] && [ -n "$PROXY_INPUT" ]; then
    echo "SAVED_PROXY=\"$PROXY_INPUT\"" > "$CONFIG_FILE"
fi

TARGET_URL="https://api.binance.com/api/v3/time"

echo ""
if [ "$MODE" == "proxy" ]; then
    echo ">>> 模式: 代理转发 ($PROXY_INPUT)"
else
    echo ">>> 模式: 直连测试 (不使用代理)"
    PROXY_INPUT=""
fi
echo "-------------------------------------------------------"

# Check dependencies
if ! command -v curl >/dev/null; then
    echo "错误: 未找到 curl。"
    exit 1
fi

HAS_BC=false
if command -v bc >/dev/null; then HAS_BC=true; fi

SUCCESS=0
FAIL=0
TOTAL_TIME_SEC=0
MIN_TIME=9999
MAX_TIME=0
TOTAL_REQ=10

echo "开始测试 (10次请求)..."

for ((i=1; i<=TOTAL_REQ; i++)); do
    # Curl command construction
    CURL_CMD="curl -s -w %{http_code}:%{time_total} -o /dev/null -m 5"
    if [ "$MODE" == "proxy" ]; then
        CURL_CMD="$CURL_CMD --proxy $PROXY_INPUT"
    fi
    CURL_CMD="$CURL_CMD $TARGET_URL"
    
    RES=$((eval $CURL_CMD))
    
    HTTP_CODE=$(echo "$RES" | cut -d: -f1)
    TIME_VAL=$(echo "$RES" | cut -d: -f2)
    
    if [ "$HTTP_CODE" == "200" ]; then
        ((SUCCESS++))
        STATUS="OK"
        
        if [ "$HAS_BC" = "true" ]; then
            if (( $(echo "$TIME_VAL < $MIN_TIME" | bc -l) )); then MIN_TIME=$TIME_VAL; fi
            if (( $(echo "$TIME_VAL > $MAX_TIME" | bc -l) )); then MAX_TIME=$TIME_VAL; fi
            TOTAL_TIME_SEC=$(echo "$TOTAL_TIME_SEC + $TIME_VAL" | bc -l)
            TIME_MS=$(echo "$TIME_VAL * 1000" | bc -l)
            printf "[%02d/10] %s - %.2f ms\n" "$i" "$STATUS" "$TIME_MS"
        else
            # Fallback integer math
            # Remove decimal point for rough sum
            TOTAL_TIME_SEC=$(echo "$TOTAL_TIME_SEC + $TIME_VAL" | bc 2>/dev/null || echo 0) 
            echo "["i"/10] $STATUS - ${TIME_VAL}s"
        fi
    else
        ((FAIL++))
        STATUS="FAIL("$HTTP_CODE")"
        echo "["i"/10] $STATUS"
    fi
done

echo ""
echo "======================================================="
echo "   测 试 报 告   "
echo "======================================================="

if [ "$SUCCESS" -eq 0 ]; then
    echo "🔴 全部失败。"
else
    if [ "$HAS_BC" = "true" ]; then
        AVG_SEC=$(echo "$TOTAL_TIME_SEC / $SUCCESS" | bc -l)
        AVG_MS=$(echo "$AVG_SEC * 1000" | bc -l)
        MIN_MS=$(echo "$MIN_TIME * 1000" | bc -l)
        MAX_MS=$(echo "$MAX_TIME * 1000" | bc -l)
        
        printf "成功: %d/%d\n" "$SUCCESS" "$TOTAL_REQ"
        printf "平均: %.2f ms\n" "$AVG_MS"
        printf "波动: %.2f ms - %.2f ms\n" "$MIN_MS" "$MAX_MS"
        
        if (( $(echo "$AVG_MS < 200" | bc -l) )); then
            echo "🟢 状态: 极速 (适合HFT)"
        elif (( $(echo "$AVG_MS < 500" | bc -l) )); then
            echo "🟡 状态: 良好"
        else
            echo "🔴 状态: 延迟高"
        fi
    else
        echo "成功: $SUCCESS/$TOTAL_REQ"
        echo "(安装 bc 以查看毫秒级数据)"
    fi
fi
EOF

chmod +x ./bnb-test-temp

if [ "$OS_TYPE" == "windows" ]; then
    echo "Windows 环境 (Git Bash): 将脚本移动到当前用户目录..."
    mv ./bnb-test-temp "$HOME/$CMD_NAME"
    echo "安装完成！您可以直接运行: ~/$CMD_NAME"
else
    echo "正在安装到 $INSTALL_DIR ..."
    $SUDO mv ./bnb-test-temp "$INSTALL_DIR/$CMD_NAME"
    if [ $? -eq 0 ]; then
        echo "✅ 安装成功！"
        echo "您现在可以在终端任何地方输入 '$CMD_NAME' 来启动测试。"
    else
        echo "❌ 安装失败。请检查权限。"
        rm ./bnb-test-temp
    fi
fi
