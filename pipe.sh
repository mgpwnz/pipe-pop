#!/bin/bash

# Перевірка на наявність curl і wget
command -v curl >/dev/null 2>&1 || { echo "curl не знайдено, будь ласка, встановіть curl."; exit 1; }
command -v wget >/dev/null 2>&1 || { echo "wget не знайдено, будь ласка, встановіть wget."; exit 1; }

# Функція для отримання останньої доступної версії
get_latest_version() {
    local BASE_URL="$1"
    local APP_NAME="$2"
    local START_VERSION="$3"

    local MAJOR=$(echo "$START_VERSION" | cut -d. -f1 | tr -d 'v')
    local MINOR=$(echo "$START_VERSION" | cut -d. -f2)
    local PATCH=$(echo "$START_VERSION" | cut -d. -f3)

    local LAST_VERSION=""

    check_version() {
        local VERSION="v${MAJOR}.${MINOR}.${PATCH}"
        local URL="${BASE_URL}/${VERSION}/${APP_NAME}"
        local HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -I "$URL")

        if [ "$HTTP_CODE" -eq 200 ]; then
            LAST_VERSION=$VERSION
            return 0
        else
            return 1
        fi
    }

    while true; do
        if check_version; then
            ((PATCH++))
        else
            if [ "$PATCH" -gt 0 ]; then
                ((PATCH--))
                LAST_VERSION="v${MAJOR}.${MINOR}.${PATCH}"
            fi
            PATCH=0
            ((MINOR++))  # Переходимо до наступної мінорної версії
            if ! check_version; then
                ((MINOR--))
                break
            fi
        fi
    done

    echo "$LAST_VERSION"
}

LATEST_VERSION=$(get_latest_version "https://dl.pipecdn.app" "pop" "v0.2.0")

# Функція для зупинки і відключення сервісу pop
stop_and_disable_pop() {
    sudo systemctl stop pop
    sudo systemctl disable pop
}

# Меню
PS3='Select an action: '
options=("Install" "Update" "Logs" "AutoUpdate" "Ref" "Uninstall" "Exit")

select opt in "${options[@]}"; do
    case $opt in
        "Install")
            cd $HOME
            sudo mkdir -p $HOME/opt/dcdn/download_cache
            sudo wget -O $HOME/opt/dcdn/pop "https://dl.pipecdn.app/$LATEST_VERSION/pop"
            sudo chmod +x $HOME/opt/dcdn/pop
            
            # Перевірка наявності символічного лінку
            if [ ! -L /usr/local/bin/pop ]; then
                sudo ln -s $HOME/opt/dcdn/pop /usr/local/bin/pop
            fi

            echo "Enter solana wallet: "
            read PUB_KEY
            echo "Enter REF code (optional): "
            read REF

            if [ -n "$REF" ]; then
                cd $HOME/opt/dcdn/
                ./pop --signup-by-referral-route "$REF"
            fi

            sudo tee /etc/systemd/system/pop.service > /dev/null << EOF
[Unit]
Description=Pipe POP Node Service
After=network.target
Wants=network-online.target

[Service]
ExecStart=$HOME/opt/dcdn/pop --ram=4 --pubKey $PUB_KEY --max-disk 150 --cache-dir $HOME/opt/dcdn/download_cache
Restart=always
RestartSec=5
LimitNOFILE=65536
LimitNPROC=4096
StandardOutput=journal
StandardError=journal
SyslogIdentifier=dcdn-node
WorkingDirectory=$HOME/opt/dcdn

[Install]
WantedBy=multi-user.target
EOF

            sudo systemctl daemon-reload
            sudo systemctl enable pop
            sudo systemctl start pop
            break
            ;;

        "Update")
            cd $HOME
            mkdir -p $HOME/pipe_backup
            cp $HOME/opt/dcdn/node_info.json $HOME/pipe_backup/node_info.json

            CURRENT_VERSION=$($HOME/opt/dcdn/pop --version 2>/dev/null)
            if [ "$CURRENT_VERSION" == "$LATEST_VERSION" ]; then
                echo "Ви вже використовуєте останню версію: $CURRENT_VERSION"
                break
            fi

            stop_and_disable_pop

            sudo wget -O $HOME/opt/dcdn/pop "https://dl.pipecdn.app/$LATEST_VERSION/pop"
            sudo chmod +x $HOME/opt/dcdn/pop
            sudo ln -s $HOME/opt/dcdn/pop /usr/local/bin/pop -f

            $HOME/opt/dcdn/pop --refresh

            sudo systemctl start pop
            sleep 2
            journalctl -n 100 -f -u pop -o cat
            break
            ;;

        "Logs")
            journalctl -n 100 -f -u pop -o cat
            break
            ;;

        "AutoUpdate")
            echo "Auto-update feature is under development."
            break
            ;;

        "Ref")
            $HOME/opt/dcdn/pop --gen-referral-route
            break
            ;;

        "Uninstall")
            if [ ! -d "$HOME/opt/dcdn" ]; then
                echo "No installation found."
                break
            fi

            read -r -p "Wipe all DATA? [y/N] " response
            case "$response" in
                [yY][eE][sS]|[yY]) 
                    echo "🔴 Початок процесу видалення Pipe POP Node..."
                    stop_and_disable_pop
                    sudo rm -f /etc/systemd/system/pop.service
                    sudo systemctl daemon-reload

                    mkdir -p $HOME/pipe_backup
                    cp $HOME/opt/dcdn/node_info.json $HOME/pipe_backup/node_info.json

                    rm -rf $HOME/opt/dcdn
                    sudo rm -f /usr/local/bin/pop

                    sudo journalctl --vacuum-time=1s  # Очищення старих логів

                    echo "✅ Видалення завершено успішно!"
                    ;;

                *)
                    echo "❌ Видалення скасовано."
                    ;;
            esac
            break
            ;;

        "Exit")
            exit
            ;;

        *)
            echo "Invalid option $REPLY"
            ;;
    esac
done
