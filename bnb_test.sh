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
        # Construct curl command
        # We capture http_code and time_total
        # Capture stderr for debugging
        CURL_CMD="curl -s -S -w %{http_code}:%{time_total} -o /dev/null -m 5"
        if [ "$mode" == "proxy" ]; then
            CURL_CMD="$CURL_CMD --proxy $proxy"
        fi
        CURL_CMD="$CURL_CMD $TARGET_URL"
        
        # Run curl, capture stdout to RES, stderr to temp file
        ERR_FILE=$(mktemp)
        RES=$(eval "$CURL_CMD" 2>"$ERR_FILE")
        CURL_RET=$?
        
        HTTP_CODE=$(echo "$RES" | cut -d: -f1)
        TIME_VAL=$(echo "$RES" | cut -d: -f2)
        
        if [ "$CURL_RET" -eq 0 ] && [ "$HTTP_CODE" == "200" ]; then
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
                TIME_INT=${TIME_VAL%.*}
                TOTAL_TIME_SEC=$((TOTAL_TIME_SEC + TIME_INT)) 
                echo "[$i/10] $STATUS - ${TIME_VAL}s"
            fi
        else
            ((FAIL++))
            # Read error message (first line only to keep it clean)
            ERR_MSG=$(head -n 1 "$ERR_FILE")
            if [ -z "$ERR_MSG" ]; then ERR_MSG="HTTP $HTTP_CODE"; fi
            
            STATUS="FAIL"
            printf "[%02d/10] %s - %s\n" "$i" "$STATUS" "$ERR_MSG"
        fi
        rm -f "$ERR_FILE"
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
        echo "配置文件已删除。"
        
        # Explicitly look for the binary in common install path
        TARGET="/usr/local/bin/bnb-test"
        if [ ! -f "$TARGET" ]; then
            # Fallback to command -v
            TARGET=$(command -v bnb-test)
        fi
        
        if [ -z "$TARGET" ]; then
            echo "错误: 找不到 bnb-test 可执行文件。"
            exit 1
        fi

        echo "正在删除 $TARGET ..."
        if rm "$TARGET" 2>/dev/null; then
             echo "✅ 卸载完成。"
        else
             echo "权限不足，正在尝试使用 sudo 删除..."
             if sudo rm "$TARGET"; then
                 echo "✅ 卸载完成。"
             else
                 echo "❌ 卸载失败。请手动运行: sudo rm $TARGET"
             fi
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
                # Simple validation
                if [[ "$proxy_input" != *"://"* ]]; then
                    echo "错误: 代理地址格式不正确 (必须包含 ://)"
                    echo "示例: socks5h://user:pass@ip:port"
                    sleep 2
                else
                    run_test "proxy" "$proxy_input"
                fi
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
