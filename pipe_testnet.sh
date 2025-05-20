#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------
# POP Cache Node Setup & Update Script
# Automates installation, optimization, configuration,
# and management of the POP Cache Node on Linux.
# -------------------------------------------------------------

# Configuration paths
CONFIG_DIR="/opt/popcache"
LOG_DIR="$CONFIG_DIR/logs"
CONFIG_JSON="$CONFIG_DIR/config.json"
ENV_FILE="$CONFIG_DIR/.env.pop"

# System files
SYSCTL_CONF="/etc/sysctl.d/99-popcache.conf"
LIMITS_CONF="/etc/security/limits.d/popcache.conf"
SERVICE_FILE="/etc/systemd/system/popcache.service"
LOGROTATE_CONF="/etc/logrotate.d/popcache"

# Binary download
BINARY_TAR_URL="https://download.pipe.network/static/pop-v0.3.0-linux-x64.tar.gz"
BINARY_TAR="/tmp/pop-v0.3.0-linux-x64.tar.gz"
BINARY_PATH="$CONFIG_DIR/pop"

# Helper for section headers
echo_header() { echo -e "\n===== $1 ====="; }

# Ensure script run as root
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root." >&2
  exit 1
fi

# 1. Check and build glibc 2.39 if necessary
echo_header "Checking glibc version"
CURRENT_GLIBC=$(ldd --version | head -n1 | awk '{print $NF}')
REQUIRED_GLIBC="2.39"
if printf '%s
%s' "$REQUIRED_GLIBC" "$CURRENT_GLIBC" | sort -V | head -n1 | grep -qx "$REQUIRED_GLIBC"; then
  echo "glibc $CURRENT_GLIBC detected (>= $REQUIRED_GLIBC)"
else
  echo "Building glibc $REQUIRED_GLIBC (this may take 3-5 minutes)..."
  mkdir -p /opt/glibc-build
  cd /opt/glibc-build
  if [[ ! -f glibc-2.39.tar.gz ]]; then
    wget http://ftp.gnu.org/gnu/libc/glibc-2.39.tar.gz
  fi
  tar -xf glibc-2.39.tar.gz
  mkdir -p glibc-2.39-build glibc-2.39-install
  cd glibc-2.39-build
  ../glibc-2.39/configure --prefix=/opt/glibc-build/glibc-2.39-install
  make -j"$(nproc)"
  make install
  export LD_LIBRARY_PATH="/opt/glibc-build/glibc-2.39-install/lib:$LD_LIBRARY_PATH"
  echo "glibc $REQUIRED_GLIBC built and installed to /opt/glibc-build/glibc-2.39-install"
fi

# 2. Install dependencies
echo_header "Installing dependencies"
apk_cmd="apt"
if ! command -v apt &>/dev/null; then
  apk_cmd="apk" # fallback if alpine
fi
$apk_cmd update -y || true
$apk_cmd install -y libssl-dev ca-certificates curl jq tar libcap2-bin authbind

# 2. Create user
echo_header "Creating 'popcache' user"
id popcache &>/dev/null || useradd -m -s /bin/bash popcache
echo "User 'popcache' ready."

# 3. Kernel tuning
echo_header "Applying sysctl optimizations"
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
echo_header "Configuring file limits"
cat > "$LIMITS_CONF" <<EOL
*    soft nofile 65535
*    hard nofile 65535
EOL

# 5. Prepare directories
echo_header "Preparing directories"
mkdir -p "$CONFIG_DIR" "$LOG_DIR"
chown -R popcache:popcache "$CONFIG_DIR"

# 6. Download and extract binary
echo_header "Downloading and extracting binary"
curl -sSL "$BINARY_TAR_URL" -o "$BINARY_TAR"
temp_dir=$(mktemp -d)
tar -xzf "$BINARY_TAR" -C "$temp_dir"
BINARY_SRC=$(find "$temp_dir" -type f -name pop -print -quit)
if [[ -z "$BINARY_SRC" ]]; then
  echo "Error: 'pop' binary not found" >&2
  rm -rf "$temp_dir" "$BINARY_TAR"
  exit 1
fi
mv "$BINARY_SRC" "$BINARY_PATH"
rm -rf "$temp_dir" "$BINARY_TAR"
chmod +x "$BINARY_PATH"
chown popcache:popcache "$BINARY_PATH"

# 7. Enable low-port binding
echo_header "Setting binding capabilities"
if setcap 'cap_net_bind_service=+ep' "$BINARY_PATH"; then
  echo "setcap succeeded"
else
  echo "setcap failed, configuring authbind" >&2
  mkdir -p /etc/authbind/byport
  touch /etc/authbind/byport/443
  chown popcache /etc/authbind/byport/443
  chmod 500 /etc/authbind/byport/443
fi

# 8. Load or prompt configuration
echo_header "Loading or creating .env.pop"
if [[ -f "$ENV_FILE" ]]; then
  source "$ENV_FILE"
  echo "Loaded existing configuration."
else
  echo "Enter POP Cache Node configuration:";
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
  chmod 600 "$ENV_FILE"; chown popcache:popcache "$ENV_FILE"
  source "$ENV_FILE"
  echo "Configuration saved to $ENV_FILE"
fi

# 9. Generate config.json
echo_header "Writing config.json"
cat > "$CONFIG_JSON" <<EOL
{
  "pop_name": "$POP_NAME",
  "pop_location": "$POP_LOCATION",
  "invite_code": "$INVITE_CODE",
  "server": { "host": "$SERVER_HOST", "port": $SERVER_PORT, "http_port": $HTTP_PORT, "workers": $WORKERS },
  "cache_config": { "memory_cache_size_mb": $MEMORY_CACHE, "disk_cache_path": "./cache", "disk_cache_size_gb": $DISK_CACHE, "default_ttl_seconds": 86400, "respect_origin_headers": true, "max_cacheable_size_mb": 1024 },
  "api_endpoints": { "base_url": "https://dataplane.pipenetwork.com" },
  "identity_config": { "node_name": "$NODE_NAME", "name": "$OP_NAME", "email": "$OP_EMAIL", "website": "$OP_WEBSITE", "twitter": "$OP_TWITTER", "discord": "$OP_DISCORD", "telegram": "$OP_TELEGRAM", "solana_pubkey": "$SOLANA_PUBKEY" }
}
EOL
chown popcache:popcache "$CONFIG_JSON"

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
ExecStart=/usr/bin/authbind --deep $BINARY_PATH
Restart=always
RestartSec=5
LimitNOFILE=65535
# Ensure binding capabilities
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
StandardOutput=append:$LOG_DIR/stdout.log
StandardError=append:$LOG_DIR/stderr.log
Environment=POP_CONFIG_PATH=$CONFIG_JSON

[Install]
WantedBy=multi-user.target
EOL
systemctl daemon-reload
systemctl enable popcache
systemctl restart popcache

# 11. Log rotation
echo_header "Setting up logrotate"
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
echo_header "Configuring firewall"
if command -v ufw &>/dev/null; then
  ufw allow "$SERVER_PORT/tcp"
  ufw allow "$HTTP_PORT/tcp"
fi

echo_header "Installation/update complete"
echo "Check service status: sudo systemctl status popcache"
