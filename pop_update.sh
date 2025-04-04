#!/bin/bash

SERVICE_NAME="pop"
LOG_LINES=100
TARGET_PATH="$HOME/opt/dcdn/pop"
ENV_PATH="$HOME/opt/dcdn/.env"

# === Load environment variables from .env ===
if [ -f "$ENV_PATH" ]; then
    source "$ENV_PATH"
else
    echo "❌ .env file not found. Please reinstall or configure Telegram settings."
    exit 1
fi

# === Function to send a Telegram notification (only if token and chat ID are set) ===
send_telegram_message() {
    local message="$1"

    # Do nothing if Telegram is not configured
    if [[ -z "$TELEGRAM_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
        return
    fi

    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d text="$message" > /dev/null
}

# === Function to check for updates in logs ===
check_for_update() {
    local log_output version

    # Look for update indication in logs
    log_output=$(journalctl -u "$SERVICE_NAME" -o cat --no-pager -n $LOG_LINES | grep -F "UPDATE AVAILABLE!")

    if [[ -n "$log_output" ]]; then
        # Extract version number after 'Latest version:'
        version=$(journalctl -u "$SERVICE_NAME" -o cat --no-pager -n $LOG_LINES | grep -oP 'Latest version:\s*\K[0-9]+\.[0-9]+\.[0-9]+' | tail -1)

        if [[ -z "$version" ]]; then
            echo "⚠️ No version found in logs."
            exit 0
        fi

        local new_version_url="https://dl.pipecdn.app/v$version/pop"
        echo "New update detected: $new_version_url"
        send_telegram_message "🔄 Pop Node update to version $version is starting..."

        update_pop "$new_version_url"

        send_telegram_message "✅ Pop Node has been successfully updated to version $version."
    fi
}

# === Function to perform the update ===
update_pop() {
    local url="$1"

    echo "Stopping pop service..."
    sudo systemctl stop pop

    echo "Downloading new version: $url"
    sudo wget -O "$TARGET_PATH" "$url"

    echo "Applying executable permissions..."
    chmod +x "$TARGET_PATH"
    sudo ln -sf "$TARGET_PATH" /usr/local/bin/pop

    echo "Refreshing and restarting pop service..."
    "$TARGET_PATH" --refresh
    sudo systemctl start pop

    echo "✅ Update complete."
}

# === Run update check ===
check_for_update
