#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
  echo "请使用 root 权限运行此脚本"
  exit 1
fi

# Get arguments
USER=${1}
PASS=${2}
PORT=${3:-1080}

# Function to read input directly from TTY
get_input() {
    PROMPT="$1"
    DEFAULT="$2"
    IS_SECURE="$3"
    
    # Try to find available TTY
    if [ -c "/dev/tty" ]; then
        TTY_DEV="/dev/tty"
    else
        echo "错误: 无法访问控制台终端。如果您在使用 curl | bash，请尝试使用 bash <(curl ...)" >&2
        exit 1
    fi

    if [ "$IS_SECURE" = "true" ]; then
        # Password input
        printf "%s" "$PROMPT" > "$TTY_DEV"
        read -r -s INPUT < "$TTY_DEV"
        echo "" > "$TTY_DEV" # Newline after password
    else
        # Normal input
        printf "%s" "$PROMPT" > "$TTY_DEV"
        read -r INPUT < "$TTY_DEV"
    fi
    
    if [ -z "$INPUT" ]; then
        echo "$DEFAULT"
    else
        echo "$INPUT"
    fi
}

if [ -z "$USER" ]; then
    USER=$(get_input "请输入 SOCKS5 用户名: " "")
fi

# Validate USER is not empty
if [ -z "$USER" ]; then
    echo "错误: 用户名不能为空。"
    exit 1
fi

if [ -z "$PASS" ]; then
    PASS=$(get_input "请输入 SOCKS5 密码: " "" "true")
fi

# Validate PASS is not empty
if [ -z "$PASS" ]; then
    echo "错误: 密码不能为空。"
    exit 1
fi

if [ -z "$PORT" ] || [ "$PORT" = "1080" ]; then
    # If PORT was passed as arg but default (or empty check fell through), confirm with user
    # But here logic is: if arg is empty, ask.
    PORT=$(get_input "请输入 SOCKS5 端口 (默认 1080): " "1080")
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

# Track the initial user
USER_FILE="/etc/socks5_users"
if [ ! -f "$USER_FILE" ]; then
    touch "$USER_FILE"
fi
if ! grep -q "^$USER$" "$USER_FILE"; then
    echo "$USER" >> "$USER_FILE"
fi

# Allow port in ufw if active
if ufw status | grep -q "Status: active"; then
    ufw allow $PORT/tcp
    echo "已在 UFW 防火墙中开放端口 $PORT。"
fi

# Restart service
systemctl restart danted
systemctl enable danted

# Create 'am' management script
cat > /usr/local/bin/am <<'EOF'
#!/bin/bash

USER_FILE="/etc/socks5_users"

# Ensure user file exists
if [ ! -f "$USER_FILE" ]; then
    touch "$USER_FILE"
fi

function check_root() {
    if [ "$EUID" -ne 0 ]; then 
      echo "请使用 root 权限运行 am 命令"
      exit 1
    fi
}

function add_user() {
    read -p "请输入新用户名: " NEW_USER
    if id "$NEW_USER" &>/dev/null; then
        echo "错误: 用户 $NEW_USER 已存在。"
        read -s -p "按回车键继续..."
        return
    fi
    read -s -p "请输入密码: " NEW_PASS
    echo ""
    
    useradd -r -s /bin/false "$NEW_USER"
    echo "$NEW_USER:$NEW_PASS" | chpasswd
    echo "$NEW_USER" >> "$USER_FILE"
    echo "用户 $NEW_USER 添加成功！"
    read -s -p "按回车键继续..."
}

function del_user() {
    echo "当前用户列表:"
    cat "$USER_FILE"
    echo "------------------------"
    read -p "请输入要删除的用户名: " DEL_USER
    
    if ! id "$DEL_USER" &>/dev/null; then
        echo "错误: 用户不存在。"
    else
        userdel "$DEL_USER"
        sed -i "/^$DEL_USER$/d" "$USER_FILE"
        echo "用户 $DEL_USER 已删除。"
    fi
    read -s -p "按回车键继续..."
}

function mod_user() {
    echo "当前用户列表:"
    cat "$USER_FILE"
    echo "------------------------"
    read -p "请输入要修改密码的用户名: " MOD_USER
    
    if ! id "$MOD_USER" &>/dev/null; then
        echo "错误: 用户不存在。"
    else
        read -s -p "请输入新密码: " NEW_PASS
        echo ""
        echo "$MOD_USER:$NEW_PASS" | chpasswd
        echo "用户 $MOD_USER 密码修改成功。"
    fi
    read -s -p "按回车键继续..."
}

function list_users() {
    echo "=== SOCKS5 用户列表 ==="
    if [ -s "$USER_FILE" ]; then
        cat "$USER_FILE"
    else
        echo "(无用户记录)"
    fi
    echo "======================"
    read -s -p "按回车键继续..."
}

function check_status() {
    echo "=== SOCKS5 运行状态 ==="
    if systemctl is-active --quiet danted; then
        echo "状态: 正在运行 (Active)"
        echo "监听端口: $(grep 'port =' /etc/danted.conf | awk '{print $4}')"
        echo "公网地址: $(curl -s ifconfig.me)"
    else
        echo "状态: 未运行 (Inactive)"
        echo "正在尝试获取详细状态..."
        systemctl status danted --no-pager
    fi
    echo "======================"
    read -s -p "按回车键继续..."
}

function view_config() {
    PUBLIC_IP=$(curl -s ifconfig.me)
    SOCKS_PORT=$(grep 'port =' /etc/danted.conf | awk '{print $4}')
    
    echo "=== SOCKS5 配置信息 ==="
    if [ -s "$USER_FILE" ]; then
        while read -r U; do
            echo "------------------------"
            echo "用户名: $U"
            echo "普通格式: IP: $PUBLIC_IP, 账号: $U, 密码: (请填写您的密码), 端口: $SOCKS_PORT"
            echo "URL 格式 (SOCKS5): socks5://$U:(请填写您的密码)@$PUBLIC_IP:$SOCKS_PORT"
            echo "URL 格式 (SOCKS5h): socks5h://$U:(请填写您的密码)@$PUBLIC_IP:$SOCKS_PORT"
        done < "$USER_FILE"
    else
        echo "(无用户记录，请先添加用户)"
    fi
    echo "======================"
    read -s -p "按回车键继续..."
}

function uninstall() {
    read -p "确定要卸载 SOCKS5 服务及所有配置吗？(y/n): " CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        echo "取消卸载。"
        read -s -p "按回车键继续..."
        return
    fi

    echo "正在停止服务..."
    systemctl stop danted
    systemctl disable danted
    
    echo "正在删除程序..."
    apt-get remove --purge -y dante-server
    apt-get autoremove -y
    
    echo "正在删除用户..."
    if [ -f "$USER_FILE" ]; then
        while read -r U; do
            if id "$U" &>/dev/null; then
                userdel "$U"
                echo "已删除用户: $U"
            fi
        done < "$USER_FILE"
        rm "$USER_FILE"
    fi

    echo "正在删除配置文件..."
    rm -f /etc/danted.conf
    rm -f /usr/local/bin/am
    rm -f /etc/danted.conf.bak

    echo "卸载完成。"
    exit 0
}

function show_menu() {
    check_root
    while true; do
        clear
        echo "=================================="
        echo "       AM SOCKS5 管理面板        "
        echo "=================================="
        echo "1. 添加用户 (Add User)"
        echo "2. 删除用户 (Delete User)"
        echo "3. 修改密码 (Change Pass)"
        echo "4. 用户列表 (List Users)"
        echo "5. 运行状态 (Check Status)"
        echo "6. 查看配置信息 (View Config)"
        echo "7. 卸载程序 (Uninstall)"
        echo "0. 退出 (Exit)"
        echo "=================================="
        read -p "请输入选项 [0-7]: " num
        case "$num" in
            1) add_user ;;
            2) del_user ;;
            3) mod_user ;;
            4) list_users ;;
            5) check_status ;;
            6) view_config ;;
            7) uninstall ;;
            0) exit 0 ;;
            *) echo "无效选项"; sleep 1 ;;
        esac
    done
}

show_menu
EOF
chmod +x /usr/local/bin/am

# Check status
if systemctl is-active --quiet danted; then
    echo "=========================================="
    echo "SOCKS5 服务器已安装并成功运行！"
    echo "地址: $(curl -s ifconfig.me):$PORT"
    echo "用户:    $USER"
    echo "密码:    ******"
    echo ""
    echo "管理命令: am"
    echo "=========================================="
else
    echo "错误: dante-server 启动失败。"
    systemctl status danted
fi
