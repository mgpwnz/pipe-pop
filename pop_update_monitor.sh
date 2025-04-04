#!/bin/bash

SERVICE_NAME="pop"
CHECK_INTERVAL=60  # Time in seconds between log checks
ENV_FILE=".env"

# === Завантаження змінних з .env, якщо існує ===
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
fi

# === Якщо змінних нема — запитати у користувача ===
if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
    read -p "Введіть Telegram Bot Token: " TELEGRAM_BOT_TOKEN
    read -p "Введіть Telegram Chat ID: " TELEGRAM_CHAT_ID

    # Зберігаємо в .env файл
    echo "TELEGRAM_BOT_TOKEN=\"$TELEGRAM_BOT_TOKEN\"" > "$ENV_FILE"
    echo "TELEGRAM_CHAT_ID=\"$TELEGRAM_CHAT_ID\"" >> "$ENV_FILE"
    echo ".env файл створено з введеними даними."
fi

# === Функція надсилання повідомлення в Telegram ===
send_telegram_message() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d text="$message" \
        -d parse_mode="Markdown" > /dev/null
}

# === Перевірка оновлення в логах ===
check_for_update() {
    local log_output
    log_output=$(journalctl -u "$SERVICE_NAME" -o cat --no-pager -n 100 | grep -oP 'Latest version:\s*\K[0-9]+\.[0-9]+\.[0-9]+' | tail -1)

    if [[ -n "$log_output" ]]; then
        local new_version="$log_output"
        local new_version_url="https://dl.pipecdn.app/v${new_version}/pop"

        echo "New update detected: version $new_version"
        send_telegram_message "🆕 Update detected for *$SERVICE_NAME*: version *$new_version*\nDownloading from: $new_version_url"
        update_pop "$new_version_url" "$new_version"
    else
        echo "No update found."
    fi
}

# === Оновлення binary ===
update_pop() {
    local url="$1"
    local version="$2"
    local target_path="$HOME/opt/dcdn/pop"

    echo "Stopping $SERVICE_NAME service..."
    sudo systemctl stop "$SERVICE_NAME"

    echo "Downloading new version: $url"
    if sudo wget -O "$target_path" "$url"; then
        echo "Applying executable permissions..."
        chmod +x "$target_path"
        sudo ln -sf "$target_path" /usr/local/bin/pop

        echo "Refreshing and restarting service..."
        "$target_path" --refresh
        sudo systemctl start "$SERVICE_NAME"

        echo "Update complete!"
        send_telegram_message "✅ *$SERVICE_NAME* successfully updated to version *$version* and restarted."
    else
        echo "Download failed."
        send_telegram_message "❌ Failed to download *$SERVICE_NAME* version *$version*."
    fi
}

# === Головний цикл ===
while true; do
    check_for_update
    sleep $CHECK_INTERVAL
done
