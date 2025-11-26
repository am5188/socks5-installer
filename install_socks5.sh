#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root"
  exit 1
fi

# Get arguments or prompt
USER=${1}
PASS=${2}
PORT=${3:-1080}

if [ -z "$USER" ]; then
    read -p "Enter SOCKS5 Username: " USER
fi

if [ -z "$PASS" ]; then
    read -s -p "Enter SOCKS5 Password: " PASS
    echo ""
fi

if [ -z "$PORT" ]; then
    read -p "Enter SOCKS5 Port (default 1080): " PORT
    PORT=${PORT:-1080}
fi

echo "Installing SOCKS5 server with:"
echo "User: $USER"
echo "Port: $PORT"

# Update and install dante-server
apt-get update
apt-get install -y dante-server

# Detect network interface
INTERFACE=$(ip route get 1.1.1.1 | awk '{print $5; exit}')
if [ -z "$INTERFACE" ]; then
    INTERFACE="eth0"
fi
echo "Detected interface: $INTERFACE"

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
    echo "User $USER already exists, updating password..."
else
    echo "Creating user $USER..."
    useradd -r -s /bin/false $USER
fi
echo "$USER:$PASS" | chpasswd

# Allow port in ufw if active
if ufw status | grep -q "Status: active"; then
    ufw allow $PORT/tcp
    echo "Allowed port $PORT in UFW."
fi

# Restart service
systemctl restart danted
systemctl enable danted

# Check status
if systemctl is-active --quiet danted; then
    echo "=========================================="
    echo "SOCKS5 Server installed and running!"
    echo "Address: $(curl -s ifconfig.me):$PORT"
    echo "User:    $USER"
    echo "Pass:    ******"
    echo "=========================================="
else
    echo "Error: dante-server failed to start."
    systemctl status danted
fi
