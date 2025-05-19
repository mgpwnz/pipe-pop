#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------
# POP Cache Node Setup Script
# Automates preparation, installation, configuration, and
# management of the POP Cache Node on Linux.
# -------------------------------------------------------------

# Variables
CONFIG_DIR="/opt/popcache"
BINARY_TAR_URL="https://download.pipe.network/static/pop-v0.3.0-linux-x64.tar.gz"
BINARY_TAR_NAME="pop-v0.3.0-linux-x64.tar.gz"
BINARY_PATH="$CONFIG_DIR/pop"
SYSCTL_CONF="/etc/sysctl.d/99-popcache.conf"
LIMITS_CONF="/etc/security/limits.d/popcache.conf"
SERVICE_FILE="/etc/systemd/system/popcache.service"
LOG_DIR="$CONFIG_DIR/logs"
LOGROTATE_CONF="/etc/logrotate.d/popcache"
ENV_FILE="$CONFIG_DIR/.env.pop"

# Ensure running as root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root. Exiting."
  exit 1
fi

# 1. Create dedicated user
if ! id popcache &>/dev/null; then
  useradd -m -s /bin/bash popcache
  usermod -aG sudo popcache
  echo "User 'popcache' created and added to sudo group."
else
  echo "User 'popcache' already exists."
fi

# 2. Install dependencies
echo "Installing required packages..."
apt update -y
apt install -y libssl-dev ca-certificates curl jq tar libcap2-bin

# 3. Optimize system network settings
cat > "$SYSCTL_CONF" <<EOL
# POP Cache Node network optimizations
net.ipv4.ip_local_port_range = 1024 65535
net.core.somaxconn = 65535
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.core.wmem_max = 16777216
net.core.rmem_max = 16777216
EOL
sysctl -p "$SYSCTL_CONF"

# 4. Increase file limits
cat > "$LIMITS_CONF" <<EOL
# POP Cache Node file limits
*    soft nofile 65535
*    hard nofile 65535
EOL

# 5. Create installation directory & logs
mkdir -p "$CONFIG_DIR"
mkdir -p "$LOG_DIR"
chown -R popcache:popcache "$CONFIG_DIR"

# 6. Download, extract and install binary
echo "Downloading POP Cache node tarball..."
curl -L "$BINARY_TAR_URL" -o "/tmp/$BINARY_TAR_NAME"
echo "Extracting binary to $CONFIG_DIR..."
tar -xzf "/tmp/$BINARY_TAR_NAME" -C "$CONFIG_DIR"

# 6a. Grant binding to low ports
echo "Setting capabilities to bind to low ports..."
setcap 'cap_net_bind_service=+ep' "$BINARY_PATH"

chmod +x "$BINARY_PATH"
chown popcache:popcache "$BINARY_PATH"
rm "/tmp/$BINARY_TAR_NAME"

# 7. Load or gather configuration input
if [[ -f "$ENV_FILE" ]]; then
  source "$ENV_FILE"
  echo "🔄 Loaded configuration from $ENV_FILE"
else
  echo -e "\nConfiguring POP Cache Node..."
  read -p "Enter POP name: " POP_NAME
  read -p "Enter POP location (City, Country): " POP_LOCATION
  read -p "Enter invite code: " INVITE_CODE

  # Server settings (defaults)
  DEFAULT_HOST="0.0.0.0"
  DEFAULT_PORT=443
  DEFAULT_HTTP_PORT=80
  DEFAULT_WORKERS=0  # 0 = auto-detect cores
  read -p "Server host [${DEFAULT_HOST}]: " SERVER_HOST
  SERVER_HOST=${SERVER_HOST:-$DEFAULT_HOST}
  read -p "Server port [${DEFAULT_PORT}]: " SERVER_PORT
  SERVER_PORT=${SERVER_PORT:-$DEFAULT_PORT}
  read -p "HTTP port [${DEFAULT_HTTP_PORT}]: " HTTP_PORT
  HTTP_PORT=${HTTP_PORT:-$DEFAULT_HTTP_PORT}
  read -p "Workers (0 = auto) [${DEFAULT_WORKERS}]: " WORKERS
  WORKERS=${WORKERS:-$DEFAULT_WORKERS}

  # Cache settings
  read -p "Memory cache size MB (e.g., 4096): " MEMORY_CACHE
  read -p "Disk cache size GB (e.g., 100): " DISK_CACHE

  # Identity settings
  read -p "Node name: " NODE_NAME
  read -p "Operator name: " OP_NAME
  read -p "Operator email: " OP_EMAIL
  read -p "Website: " OP_WEBSITE
  read -p "Twitter handle: " OP_TWITTER
  read -p "Discord username: " OP_DISCORD
  read -p "Telegram handle: " OP_TELEGRAM
  read -p "Solana wallet pubkey: " SOLANA_PUBKEY

  # Save to env file for future runs
  cat > "$ENV_FILE" <<EOL
POP_NAME="$POP_NAME"
POP_LOCATION="$POP_LOCATION"
INVITE_CODE="$INVITE_CODE"
SERVER_HOST="$SERVER_HOST"
SERVER_PORT="$SERVER_PORT"
HTTP_PORT="$HTTP_PORT"
WORKERS="$WORKERS"
MEMORY_CACHE="$MEMORY_CACHE"
DISK_CACHE="$DISK_CACHE"
NODE_NAME="$NODE_NAME"
OP_NAME="$OP_NAME"
OP_EMAIL="$OP_EMAIL"
OP_WEBSITE="$OP_WEBSITE"
OP_TWITTER="$OP_TWITTER"
OP_DISCORD="$OP_DISCORD"
OP_TELEGRAM="$OP_TELEGRAM"
SOLANA_PUBKEY="$SOLANA_PUBKEY"
EOL
  echo "✅ Saved configuration to $ENV_FILE"
fi

# 8. Write config.json
CONFIG_FILE="$CONFIG_DIR/config.json"
cat > "$CONFIG_FILE" <<EOL
{
  "pop_name": "$POP_NAME",
  "pop_location": "$POP_LOCATION",
  "invite_code": "$INVITE_CODE",
  "server": {
    "host": "$SERVER_HOST",
    "port": $SERVER_PORT,
    "http_port": $HTTP_PORT,
    "workers": $WORKERS
  },
  "cache_config": {
    "memory_cache_size_mb": $MEMORY_CACHE,
    "disk_cache_path": "./cache",
    "disk_cache_size_gb": $DISK_CACHE,
    "default_ttl_seconds": 86400,
    "respect_origin_headers": true,
    "max_cacheable_size_mb": 1024
  },
  "api_endpoints": {
    "base_url": "https://dataplane.pipenetwork.com"
  },
  "identity_config": {
    "node_name": "$NODE_NAME",
    "name": "$OP_NAME",
    "email": "$OP_EMAIL",
    "website": "$OP_WEBSITE",
    "twitter": "$OP_TWITTER",
    "discord": "$OP_DISCORD",
    "telegram": "$OP_TELEGRAM",
    "solana_pubkey": "$SOLANA_PUBKEY"
  }
}
EOL
chown popcache:popcache "$CONFIG_FILE"

# 9. Create systemd service
cat > "$SERVICE_FILE" <<EOL
[Unit]
Description=POP Cache Node
After=network.target

[Service]
Type=simple
User=popcache
Group=popcache
WorkingDirectory=$CONFIG_DIR
ExecStart=$BINARY_PATH
Restart=always
RestartSec=5
LimitNOFILE=65535
StandardOutput=append:${LOG_DIR}/stdout.log
StandardError=append:${LOG_DIR}/stderr.log
Environment=POP_CONFIG_PATH=$CONFIG_FILE

[Install]
WantedBy=multi-user.target
EOL

# Reload and enable service
systemctl daemon-reload
systemctl enable popcache
systemctl restart popcache

# 10. Configure log rotation
cat > "$LOGROTATE_CONF" <<EOL
$LOG_DIR/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 popcache popcache
    sharedscripts
    postrotate
        systemctl reload popcache >/dev/null 2>&1 || true
    endscript
}
EOL

# 11. Firewall rules (UFW)
if command -v ufw &>/dev/null; then
  ufw allow ${SERVER_PORT}/tcp
  ufw allow ${HTTP_PORT}/tcp
  echo "UFW rules added for ports ${SERVER_PORT} and ${HTTP_PORT}."
fi

# Summary
cat <<EOF

POP Cache Node installation complete!
- Service: popcache
- Logs: $LOG_DIR
- Config file: $CONFIG_FILE
To view logs: tail -f $LOG_DIR/stdout.log $LOG_DIR/stderr.log
To check service status: sudo systemctl status popcache
EOF
