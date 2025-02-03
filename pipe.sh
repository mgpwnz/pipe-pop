#!/bin/bash
while true
do
# Перевірка на наявність curl і wget
command -v curl >/dev/null 2>&1 || { echo "curl не знайдено, будь ласка, встановіть curl."; exit 1; }
command -v wget >/dev/null 2>&1 || { echo "wget не знайдено, будь ласка, встановіть wget."; exit 1; }
DISK=150
RAM=8
LATEST_VERSION=$(wget -qO- https://raw.githubusercontent.com/mgpwnz/pipe-pop/refs/heads/main/ver.sh)

# Функція для зупинки і відключення сервісу pop
stop_and_disable_pop() {
    sudo systemctl stop pop
    sudo systemctl disable pop
}
backup_node_info() {
    # Create the backup directory if it doesn't exist
    mkdir -p "$HOME/pipe_backup"

    # Check if node_info.json exists before copying
    if [ -f "$HOME/opt/dcdn/node_info.json" ]; then
        # Copy the node_info.json file to the backup directory
        cp "$HOME/opt/dcdn/node_info.json" "$HOME/pipe_backup/node_info.json"
        echo "Backup of node_info.json completed."
    else
        echo "node_info.json not found, skipping backup."
    fi
}
delete_autoupdate(){
    if [ -f "$HOME/opt/dcdn/update_node.sh" ]; then
        rm $HOME/opt/dcdn/update_node.sh
        sudo rm /etc/systemd/system/node_update.service
        sudo rm /etc/systemd/system/node_update.timer
        sudo systemctl daemon-reload
        sudo systemctl disable node_update.timer
        sudo systemctl stop node_update.timer
        echo "Автооновлення було видалене."
    fi
}
port_check() {
    local PORT=8003
    if sudo lsof -i :$PORT >/dev/null 2>&1; then
        echo "Ошибка: Порт $PORT занят. Остановка установки."
        exit 1
    else
        echo "Порт $PORT свободен. Продолжаем установку."
    fi
}
# Меню
PS3='Select an action: '
options=("Install" "Update" "Logs" "Status" "AutoUpdate" "Ref" "Uninstall" "Exit")

select opt in "${options[@]}"; do
    case $opt in
        "Install")
            cd $HOME
            port_check
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
ExecStart=$HOME/opt/dcdn/pop --ram=$RAM --pubKey $PUB_KEY --max-disk $DISK --cache-dir $HOME/opt/dcdn/download_cache
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
            #back up  
            backup_node_info

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
            #back up        
            backup_node_info
        
            # Створюємо скрипт для оновлення
            echo "Створення скрипту оновлення..."
    cat << EOF > $HOME/opt/dcdn/update_node.sh
#!/bin/bash

# Завантажуємо останню доступну версію
LATEST_VERSION=$(wget -qO- https://raw.githubusercontent.com/mgpwnz/pipe-pop/refs/heads/main/ver.sh)

# Отримуємо поточну версію програми без зайвих частин (п’яте поле)
CURRENT_VERSION=\$($HOME/opt/dcdn/pop --version | awk '{print \$5}')

# Виводимо поточну та останню версію для перевірки
echo "Поточна версія: \$CURRENT_VERSION"
echo "Остання доступна версія: \$LATEST_VERSION"

# Порівнюємо версії
if [ "\$CURRENT_VERSION" != "\$LATEST_VERSION" ]; then
    echo "Оновлення доступне! Оновлюємо версію..."

    # Зупиняємо службу
    sudo systemctl stop pop

    # Завантажуємо нову версію
    sudo wget -O $HOME/opt/dcdn/pop "https://dl.pipecdn.app/\$LATEST_VERSION/pop"
    sudo chmod +x $HOME/opt/dcdn/pop

    # Оновлюємо символьне посилання
    sudo ln -s $HOME/opt/dcdn/pop /usr/local/bin/pop -f

    # Перезапускаємо службу
    sudo systemctl start pop

    echo "Оновлення успішно завершено."
else
    echo "Ви вже використовуєте останню версію: \$CURRENT_VERSION"
fi
EOF

    sudo chmod +x $HOME/opt/dcdn/update_node.sh

    # Створюємо службу systemd для автооновлення
    sudo tee /etc/systemd/system/node_update.service > /dev/null << EOF
[Unit]
Description=Pipe POP Node Update Service
After=network.target

[Service]
ExecStart=$HOME/opt/dcdn/update_node.sh
Restart=on-failure
User=$USER
WorkingDirectory=$HOME

[Install]
WantedBy=multi-user.target
EOF

    # Створюємо таймер для виконання служби
    sudo tee /etc/systemd/system/node_update.timer > /dev/null << EOF
[Unit]
Description=Run Node Update Script Daily

[Timer]
OnBootSec=60min
OnUnitActiveSec=1d
Unit=node_update.service

[Install]
WantedBy=timers.target
EOF

            # Перезавантажуємо systemd і активуємо таймер
            sudo systemctl daemon-reload
            sudo systemctl enable node_update.timer
            sudo systemctl start node_update.timer

            echo "Автооновлення налаштоване і активоване."
            break
            ;;


        "Ref")
            $HOME/opt/dcdn/pop --gen-referral-route
            break
            ;;

        "Status")
            $HOME/opt/dcdn/pop --status
            break
            ;;
        
        "Сhange System Requirements")
            echo "Enter RAM: "
            read NEW_RAM
            echo "Enter STORAGE: "
            read STORAGE            
            sudo sed -i 's/--ram=[^ ]*/--ram=$NEW_RAM/' /etc/systemd/system/pop.service
            sudo sed -i 's/--max-disk [^ ]*/--max-disk $STORAGE/' /etc/systemd/system/pop.service
            sudo systemctl daemon-reload
            sudo systemctl restart pop
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

                    backup_node_info
                    delete_autoupdate
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
done