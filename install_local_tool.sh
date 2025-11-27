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

function run_test() {
    local mode=$1
    local proxy=$2
    
    TARGET_URL="https://api.binance.com/api/v3/time"
    echo ""
    if [ "$mode" == "proxy" ]; then
        echo ">>> 模式: 代理转发 ($proxy)"
        # Save config
        echo "SAVED_PROXY=\"$proxy\"" > "$CONFIG_FILE"
    else
        echo ">>> 模式: 直连测试 (不使用代理)"
    fi
    echo "-------------------------------------------------------"

    SUCCESS=0
    FAIL=0
    TOTAL_TIME_SEC=0
    MIN_TIME=9999
    MAX_TIME=0
    TOTAL_REQ=10
    
    HAS_BC=false
    if command -v bc >/dev/null; then HAS_BC=true; fi

    echo "开始测试 (10次请求)..."

    for ((i=1; i<=TOTAL_REQ; i++)); do
        CURL_CMD="curl -s -w %{http_code}:%{time_total} -o /dev/null -m 5"
        if [ "$mode" == "proxy" ]; then
            CURL_CMD="$CURL_CMD --proxy $proxy"
        fi
        CURL_CMD="$CURL_CMD $TARGET_URL"
        
        RES=$(eval $CURL_CMD)
        
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
                TOTAL_TIME_SEC=$(echo "$TOTAL_TIME_SEC + $TIME_VAL" | bc 2>/dev/null || echo 0) 
                echo "[$i/10] $STATUS - ${TIME_VAL}s"
            fi
        else
            ((FAIL++))
            STATUS="FAIL($HTTP_CODE)"
            echo "[$i/10] $STATUS"
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
    read -p "按回车键继续..."
}

function uninstall() {
    echo "确定要卸载 bnb-test 工具吗？(y/n)"
    read -r confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -f "$CONFIG_FILE"
        # Self-destruction needs careful handling of sudo
        if [ -w "$INSTALL_DIR/$CMD_NAME" ]; then
             rm "$INSTALL_DIR/$CMD_NAME"
             echo "卸载完成。"
        else
             echo "请使用 sudo rm $INSTALL_DIR/$CMD_NAME 手动删除命令文件。"
             echo "配置文件已删除。"
        fi
        exit 0
    else
        echo "取消卸载。"
    fi
}

while true; do
    clear
    echo "======================================="
    echo "   Binance API Benchmark Tool (Local)"
    echo "======================================="
    echo "[1] 使用本机直连测试 (Direct)"
    echo "[2] 使用 SOCKS5 代理测试 (Proxy)"
    echo "[3] 卸载此工具 (Uninstall)"
    echo "[0] 退出 (Exit)"
    echo "======================================="
    read -p "请输入选项 [0-3]: " choice
    
    case "$choice" in
        1)
            run_test "direct" ""
            ;;
        2)
            if [ -n "$SAVED_PROXY" ]; then
                read -p "使用保存的代理 ($SAVED_PROXY)? [Y/n]: " p_choice
                if [[ "$p_choice" =~ ^[Nn]$ ]]; then
                    read -p "请输入新代理 (socks5h://...): " proxy_input
                else
                    proxy_input="$SAVED_PROXY"
                fi
            else
                read -p "请输入代理 (socks5h://...): " proxy_input
            fi
            
            if [ -n "$proxy_input" ]; then
                run_test "proxy" "$proxy_input"
            else
                echo "代理地址不能为空。"
                sleep 1
            fi
            ;;
        3)
            uninstall
            ;;
        0)
            exit 0
            ;;
        *)
            echo "无效选项"
            sleep 1
            ;;
    esac
done
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