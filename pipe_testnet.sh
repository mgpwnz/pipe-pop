#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------
# POP Cache Node Setup & Update Script with Capabilities Debug
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

# Function to print header
echo_header() {
  echo -e "\n===== $1 ====="
}

# Ensure running as root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root. Exiting."
  exit 1
fi

# 1. Install dependencies
echo_header "Installing packages"
apt update -y
apt install -y libssl-dev ca-certificates curl jq tar libcap2-bin

# 2. Create dedicated user
echo_header "Ensuring 'popcache' user exists"
if ! id popcache &>/dev/null; then
  useradd -m -s /bin/bash popcache
  usermod -aG sudo popcache
  echo "User 'popcache' created."
else
  echo "User 'popcache' already exists."
fi

# 3. Optimize network settings
echo_header "Applying sysctl network optimizations"
cat > "$SYSCTL_CONF" <<EOL
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
echo_header "Setting file limits"
cat > "$LIMITS_CONF" <<EOL
*    soft nofile 65535
*    hard nofile 65535
EOL

# 5. Prepare directories
echo_header "Creating directories"
mkdir -p "$CONFIG_DIR" "$LOG_DIR"
chown -R popcache:popcache "$CONFIG_DIR"

# 6. Download & extract binary
echo_header "Downloading & extracting POP binary"
curl -sSL "$BINARY_TAR_URL" -o "/tmp/$BINARY_TAR_NAME"
temp_dir=$(mktemp -d)
tar -xzf "/tmp/$BINARY_TAR_NAME" -C "$temp_dir"
BINARY_SRC=$(find "$temp_dir" -type f -name pop -print -quit)
if [[ -z "$BINARY_SRC" ]]; then
  echo "Error: 'pop' binary not found in archive" >&2
  rm -rf "$temp_dir" "/tmp/$BINARY_TAR_NAME"
  exit 1
fi
mv "$BINARY_SRC" "$BINARY_PATH"
rm -rf "$temp_dir" "/tmp/$BINARY_TAR_NAME"

# 7. Set permissions & capabilities
echo_header "Setting permissions & capabilities"
chmod +x "$BINARY_PATH"
# Debug before
echo "Capabilities before setcap:"
getcap "$BINARY_PATH" || echo "  none"
# Apply
if setcap 'cap_net_bind_service=+ep' "$BINARY_PATH"; then
  echo "setcap applied successfully"
else
  echo "Warning: setcap failed. Ensure libcap2-bin is installed and filesystem supports capabilities." >&2
fi
# Debug after
echo "Capabilities after setcap:"
getcap "$BINARY_PATH" || echo "  none"
chown popcache:popcache "$BINARY_PATH"

# 8. Load or gather configuration
echo_header "Loading configuration"
if [[ -f "$ENV_FILE" ]]; then
  source "$ENV_FILE"
  echo "Loaded config from $ENV_FILE"
else
  echo "First run: please enter configuration values"
  read -p "POP name: " POP_NAME
  read -p "POP location (City, Country): " POP_LOCATION
  read -p "Invite code: " INVITE_CODE
  read -p "Server host [0.0.0.0]: " SERVER_HOST; SERVER_HOST=${SERVER_HOST:-0.0.0.0}
  read -p "Server port [443]: " SERVER_PORT; SERVER_PORT=${SERVER_PORT:-443}
  read -p "HTTP port [80]: " HTTP_PORT; HTTP_PORT=${HTTP_PORT:-80}
  read -p "Workers (0=auto): " WORKERS; WORKERS=${WORKERS:-0}
  read -p "Memory cache MB: " MEMORY_CACHE
  read -p "Disk cache GB: " DISK_CACHE
  read -p "Node name: " NODE_NAME
  read -p "Operator name: " OP_NAME
  read -p "Operator email: " OP_EMAIL
  read -p "Website: " OP_WEBSITE
  read -p "Twitter: " OP_TWITTER
  read -p "Discord: " OP_DISCORD
  read -p "Telegram: " OP_TELEGRAM
  read -p "Solana pubkey: " SOLANA_PUBKEY

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
  chmod 600 "$ENV_FILE" && chown popcache:popcache "$ENV_FILE"
  echo "Configuration saved to $ENV_FILE"
  source "$ENV_FILE"
fi

# 9. Write config.json
echo_header "Writing config.json"
cat > "$CONFIG_DIR/config.json" <<EOL
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
chown popcache:popcache "$CONFIG_DIR/config.json"

# 10. Systemd service setup
echo_header "Configuring systemd service"
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
StandardOutput=append:$LOG_DIR/stdout.log
StandardError=append:$LOG_DIR/stderr.log
Environment=POP_CONFIG_PATH=$CONFIG_DIR/config.json

[Install]
WantedBy=multi-user.target
EOL
systemctl daemon-reload
systemctl enable popcache
systemctl restart popcache

# 11. Log rotation
echo_header "Setting up log rotation"
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

# 12. Firewall rules
echo_header "Applying firewall rules"
if command -v ufw &>/dev/null; then
  ufw allow "$SERVER_PORT/tcp"
  ufw allow "$HTTP_PORT/tcp"
  echo "Rules added for $SERVER_PORT and $HTTP_PORT"
fi

# Done
echo_header "POP Cache Node installation/update complete"
echo "Run 'sudo systemctl status popcache' to verify service status."
