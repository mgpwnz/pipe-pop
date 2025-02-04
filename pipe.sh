#!/bin/bash 
# Check for the presence of curl and wget
install_package() {
    PACKAGE=$1
    if command -v apt >/dev/null 2>&1; then
        sudo apt update
        sudo apt install -y $PACKAGE
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y $PACKAGE
    else
        echo "Не вдалося визначити пакетний менеджер. Встановіть $PACKAGE вручну."
        exit 1
    fi
}

if ! command -v curl >/dev/null 2>&1; then
    echo "curl не знайдено. Пакет буде встановлено..."
    install_package curl
fi

if ! command -v wget >/dev/null 2>&1; then
    echo "wget не знайдено. Пакет буде встановлено..."
    install_package wget
fi

if ! command -v lsof >/dev/null 2>&1; then
    echo "lsof не знайдено. Пакет буде встановлено..."
    install_package lsof
fi

while true
do
DISK=150
RAM=8
LATEST_VERSION=$(. <(wget -qO- https://raw.githubusercontent.com/mgpwnz/pipe-pop/refs/heads/main/ver.sh))
LOG_VERSION=$(journalctl -n 100 -u pop -o cat | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | tail -1)
DEF_VERSION=0.2.2
echo -e "\e[33mLatest node version $LATEST_VERSION\e[0m"
echo -e "\e[92mInstalled node version $LOG_VERSION\e[0m"

if systemctl is-active --quiet node_update.timer; then
    echo -e "\e[32mAuto Update Active\e[0m"
else
    echo -e "\e[31mAuto Update OFF\e[0m"
fi


# Function to stop and disable the pop service
stop_and_disable_pop() {
    sudo systemctl stop pop
    sudo systemctl disable pop
}

backup_node_info() {
    # Create the backup directory if it doesn't exist
    mkdir -p "$HOME/pipe_backup"

    # Check if node_info.json exists in the backup directory before copying
    if [ ! -f "$HOME/pipe_backup/node_info.json" ]; then
        # Check if node_info.json exists in the original location
        if [ -f "$HOME/opt/dcdn/node_info.json" ]; then
            cp "$HOME/opt/dcdn/node_info.json" "$HOME/pipe_backup/node_info.json"
            echo "Backup of node_info.json completed."
        else
            echo "node_info.json not found, skipping backup."
        fi
    else
        echo "Backup already exists, skipping backup."
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
        echo "Auto-update has been removed."
    fi
}

port_check() {
    local PORT=8003
    if sudo lsof -i :$PORT >/dev/null 2>&1; then
        echo "Error: Port $PORT is in use. Stopping installation."
        exit 1
    else
        echo "Port $PORT is free. Continuing installation."
    fi
}

restore_backup(){
    if [ -f "$HOME/pipe_backup/node_info.json" ]; then
        cp "$HOME/pipe_backup/node_info.json" "$HOME/opt/dcdn/node_info.json"
        echo "Backup of node_info.json restored."
    else
        echo "Backup not found."
    fi
}
download_and_prepare_pop() {
    local max_retries=5
    local attempt=0
    local dest_dir="$HOME/opt/dcdn"
    local dest_file="$dest_dir/pop"

    sudo mkdir -p "$dest_dir/download_cache"

    while (( attempt < max_retries )); do
        sudo wget -O "$dest_file" "https://dl.pipecdn.app/v$DEF_VERSION/pop"
        if [ -s "$dest_file" ]; then
            sudo chmod +x "$dest_file"
            echo "Download successful."
            sudo rm -rf "$dest_dir/download_cache"
            return 0
        else
            echo "Downloaded file is empty, retrying... ($((attempt + 1))/$max_retries)"
            ((attempt++))
        fi
    done

    echo "Failed to download file after $max_retries attempts. Exiting."
    sudo rm -rf "$dest_dir/download_cache"
    exit 1
}
download_pop() {
    local max_retries=5
    local attempt=0
    local dest_dir="$HOME/opt/dcdn"
    local temp_file="$dest_dir/pop.tmp"

    sudo mkdir -p "$dest_dir/download_cache"

    while (( attempt < max_retries )); do
        sudo wget -O "$temp_file" "https://dl.pipecdn.app/v$LOG_VERSION/pop"
        if [ -s "$temp_file" ]; then
            echo "Download successful."
            break
        else
            echo "Downloaded file is empty, retrying... ($((attempt + 1))/$max_retries)"
            ((attempt++))
        fi
    done

    if (( attempt == max_retries )); then
        echo "Failed to download file after $max_retries attempts. Exiting."
        sudo rm -rf "$dest_dir/download_cache"
        exit 1
    fi
}


# Menu
PS3='Select an action: '
options=("Install" "Update" "Logs" "Change System Requirements" "Status" "AutoUpdate" "Rem. AutoUpdate" "Ref" "Uninstall" "Exit")

select opt in "${options[@]}"; do
    case $opt in
        "Install")
            cd $HOME
            port_check
            echo "Find latest node version $LATEST_VERSION"
            echo "Select version option:"
            echo "1) Use default version ($DEF_VERSION)"
            echo "2) Enter version manually"
            read -rp "Enter choice (1 or 2): " choice

            if [ "$choice" == "2" ]; then
                read -rp "Enter version: " DEF_VERSION
            fi
            download_and_prepare_pop

            if [ ! -L /usr/local/bin/pop ]; then
                sudo ln -s "$HOME/opt/dcdn/pop" /usr/local/bin/pop
            fi

            echo "Enter Solana wallet: "
            read PUB_KEY
            echo "Enter REF code (optional): "
            read REF

            if [ -n "$REF" ]; then
                cd $HOME/opt/dcdn/
                ./pop --signup-by-referral-route "$REF"
            fi
            restore_backup

            sudo tee /etc/systemd/system/pop.service > /dev/null << EOF
[Unit]
Description=Pipe POP Node Service
After=network.target
Wants=network-online.target

[Service]
ExecStart=$HOME/opt/dcdn/pop --ram $RAM --pubKey $PUB_KEY --max-disk $DISK --cache-dir $HOME/opt/dcdn/download_cache
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
            backup_node_info

            # Get the current version of the program
            CURRENT_VERSION=$($HOME/opt/dcdn/pop --version | awk '{print $5}')

            # Print the current and latest version for verification
            echo "Current version: $CURRENT_VERSION"
            echo "Log available version: $LOG_VERSION"

            # Comparing versions
            if [ "$CURRENT_VERSION" != "$LOG_VERSION" ]; then
                echo "Update available! Updating version..."

                # Downloading the new version as a temporary file

                download_pop

                # Stopping the service after successful download
                sudo systemctl stop pop

                # Replacing the old version with the new one
                mv "$HOME/opt/dcdn/pop.tmp" "$HOME/opt/dcdn/pop"
                sudo chmod +x "$HOME/opt/dcdn/pop"
                sudo rm -rf "$HOME/opt/dcdn/download_cache"

                # Update the symbolic link
                sudo rm -f /usr/local/bin/pop
                sudo ln -s "$HOME/opt/dcdn/pop" /usr/local/bin/pop

                # Restart the service
                sudo systemctl start pop

                echo "Update completed successfully."
            else
                echo "You are already using the latest version: $CURRENT_VERSION"
            fi
            break
            ;;

        "Logs")
            journalctl -n 100 -f -u pop -o cat
            break
            ;;

        "AutoUpdate")
        # Check if the update script exists
        if [ ! -f "$HOME/opt/dcdn/update_node.sh" ]; then
        echo "File $HOME/opt/dcdn/update_node.sh does not exist. Creating the update script..."
        backup_node_info

        # Download the update script
        wget -O $HOME/opt/dcdn/update_node.sh https://raw.githubusercontent.com/mgpwnz/pipe-pop/refs/heads/main/update_node.sh
        sudo chmod +x $HOME/opt/dcdn/update_node.sh
        else
            echo "File $HOME/opt/dcdn/update_node.sh already exists. Interrupting script execution."
            exit 1
        fi

    # Create a systemd service for auto-update
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

    # Create a timer to execute the service
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

    # Restart systemd and activate the timer
    sudo systemctl daemon-reload
    sudo systemctl enable node_update.timer
    sudo systemctl start node_update.timer

    echo "Auto-update is configured and enabled."
            break
            ;;
        "Rem. AutoUpdate")
            delete_autoupdate
            break
            ;;

        "Ref")
            cd $HOME/opt/dcdn/ && ./pop --gen-referral-route
            cd $HOME
            break
            ;;

        "Status")
            cd $HOME/opt/dcdn/ && ./pop --status
            cd $HOME
            break
            ;;
        
        "Сhange System Requirements")
            echo "Change System Requirements"
            echo "Enter RAM: "
            read NEW_RAM
            echo "Enter STORAGE: "
            read STORAGE

            sudo sed -i "s/--ram=[^ ]*/--ram=$NEW_RAM/" /etc/systemd/system/pop.service
            sudo sed -i "s/--max-disk [^ ]*/--max-disk $STORAGE/" /etc/systemd/system/pop.service

            sudo systemctl daemon-reload
            sudo systemctl restart pop
            journalctl -n 100 -f -u pop -o cat
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
                    echo "Starting the Pipe POP Node removal process..."
                    stop_and_disable_pop
                    sudo rm -f /etc/systemd/system/pop.service
                    sudo systemctl daemon-reload

                    backup_node_info
                    delete_autoupdate
                    rm -rf $HOME/opt/dcdn
                    sudo rm -f /usr/local/bin/pop

                    sudo journalctl --vacuum-time=1s

                    echo "Removal completed successfully."
                    ;;

                *)
                    echo "Uninstallation canceled."
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