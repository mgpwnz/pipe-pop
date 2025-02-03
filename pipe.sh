#!/bin/bash

# Перевірка на наявність curl і wget
command -v curl >/dev/null 2>&1 || { echo "curl не знайдено, будь ласка, встановіть curl."; exit 1; }
command -v wget >/dev/null 2>&1 || { echo "wget не знайдено, будь ласка, встановіть wget."; exit 1; }

LATEST_VERSION=$(. <(wget -qO- https://raw.githubusercontent.com/mgpwnz/pipe-pop/refs/heads/main/ver.sh))

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
            # Створюємо скрипт для оновлення
            echo "Створення скрипту оновлення..."
            cat << EOF > $HOME/opt/dcdn/update_node.sh
        #!/bin/bash
        LATEST_VERSION=$(. <(wget -qO- https://raw.githubusercontent.com/mgpwnz/pipe-pop/refs/heads/main/ver.sh))

        CURRENT_VERSION=$($HOME/opt/dcdn/pop --version | awk '{print $5}')

        if [ "\$CURRENT_VERSION" != "\$LATEST_VERSION" ]; then
            echo "Оновлення доступне! Оновлюємо версію..."

            sudo systemctl stop pop
            sudo wget -O $HOME/opt/dcdn/pop "https://dl.pipecdn.app/\$LATEST_VERSION/pop"
            sudo chmod +x $HOME/opt/dcdn/pop
            sudo ln -s $HOME/opt/dcdn/pop /usr/local/bin/pop -f

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
OnBootSec=10min
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
