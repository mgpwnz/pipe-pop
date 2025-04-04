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
        echo "Unable to determine package manager. Please install $PACKAGE manually."
        exit 1
    fi
}

if ! command -v curl >/dev/null 2>&1; then
    echo "curl not found. Will install..."
    install_package curl
fi

if ! command -v wget >/dev/null 2>&1; then
    echo "wget not found. Will install..."
    install_package wget
fi

if ! command -v lsof >/dev/null 2>&1; then
    echo "lsof not found. Will install..."
    install_package lsof
fi

while true
do
DISK=150
RAM=8
LATEST_VERSION=$(. <(wget -qO- https://raw.githubusercontent.com/mgpwnz/pipe-pop/refs/heads/main/ver.sh))
LOG_VERSION=$(journalctl -n 100 -u pop -o cat | grep -oP 'Latest version:\s*\K[0-9]+\.[0-9]+\.[0-9]+' | tail -1)
DEF_VERSION=0.2.8
#CURRENT_VERSION=$($HOME/opt/dcdn/pop --version | awk '/[0-9]+\.[0-9]+\.[0-9]+/ {for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+$/) print $i}')
CURRENT_VERSION=$($HOME/opt/dcdn/pop --version 2>/dev/null | awk '/[0-9]+\.[0-9]+\.[0-9]+/ {for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+$/) print $i}')

echo -e "\e[33mLatest node version $LATEST_VERSION\e[0m"
if [ ! -f "$HOME/opt/dcdn/pop" ]; then
echo -e "\e[31mNode is not installed!\e[0m"
else
echo -e "\e[92mInstalled node version $CURRENT_VERSION\e[0m"
fi

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
add_ports() {
    # Check if the version is empty — meaning no update is available
    if [[ -z "$LOG_VERSION" ]]; then
        echo "Checking port configuration..."

        # If the port flag is already present — do nothing
        if grep -qE '^ExecStart=.*--enable-80-443' /etc/systemd/system/pop.service; then
            echo "Port parameters already enabled. No changes needed."
        else
            echo "Port parameters not found. Applying update..."

            # Add the port flag only if it's not already present
            sed -i '/^ExecStart=/ {/--enable-80-443/! s/$/ --enable-80-443/}' /etc/systemd/system/pop.service

            # Refresh configuration
            cd "$HOME/opt/dcdn" && ./pop --refresh
            cd "$HOME"

            # Reload systemd and restart the service
            systemctl daemon-reload
            systemctl restart pop.service

            echo "Port parameters added and service restarted."
        fi
    fi
}

port_check() {
    # List of ports to check
    local PORTS=(8003 443 80)

    for PORT in "${PORTS[@]}"; do
        if sudo lsof -i :$PORT >/dev/null 2>&1; then
            echo "Error: Port $PORT is in use. Stopping installation."
            exit 1
        else
            echo "Port $PORT is free. Continuing..."
        fi
    done
}

restore_backup(){
    if [ -f "$HOME/pipe_backup/node_info.json" ]; then
        cp "$HOME/pipe_backup/node_info.json" "$HOME/opt/dcdn/node_info.json"
        echo "Backup of node_info.json restored."
    else
        echo "Backup not found."
        echo "Enter REF code (optional): "
            read REF

            if [ -n "$REF" ]; then
                cd $HOME/opt/dcdn/
                ./pop --signup-by-referral-route "$REF"
            fi
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
tg_bot() {
    ENV_PATH="$HOME/pipe_backup/.env"
    mkdir -p "$HOME/pipe_backup"

    if [ ! -f "$ENV_PATH" ]; then
        echo "Do you want to enable Telegram notifications? [y/n]"
        read -r use_telegram

        if [[ "$use_telegram" =~ ^[Yy]$ ]]; then
            echo "Enter Telegram Bot Token:"
            read TELEGRAM_TOKEN

            echo "Enter Telegram Chat ID:"
            read TELEGRAM_CHAT_ID

            echo "TELEGRAM_TOKEN=\"$TELEGRAM_TOKEN\"" > "$ENV_PATH"
            echo "TELEGRAM_CHAT_ID=\"$TELEGRAM_CHAT_ID\"" >> "$ENV_PATH"
            echo ".env file created with Telegram settings."
        else
            echo "TELEGRAM_TOKEN=\"\"" > "$ENV_PATH"
            echo "TELEGRAM_CHAT_ID=\"\"" >> "$ENV_PATH"
            echo ".env file created without Telegram settings."
        fi
    else
        echo ".env already exists. Skipping Telegram setup."
    fi
}

find_prev_install() {
    if [  -f "$HOME/opt/dcdn/pop" ]; then
echo -e "\e[31mNode is already installed\e[0m"
exit 1
else
echo -e "\e[92mInstall\e[0m"
fi
}
pre_update() {
    if [ ! -f "$HOME/opt/dcdn/pop" ]; then
echo -e "\e[31mNode is not installed!\e[0m"
echo -e "\e[31mRun Install\e[0m"
exit 1
fi
}
# Menu
PS3='Select an action: '
options=("Install" "Update" "Logs" "Change System Requirements" "Status" "AutoUpdate" "Rem. AutoUpdate" "Ref" "Points" "Uninstall" "Exit")

select opt in "${options[@]}"; do
    case $opt in
        "Install")
            cd $HOME
            find_prev_install
            port_check
            echo "Enter Solana wallet: "
            read PUB_KEY
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

            restore_backup

            sudo tee /etc/systemd/system/pop.service > /dev/null << EOF
[Unit]
Description=Pipe POP Node Service
After=network.target
Wants=network-online.target

[Service]
ExecStart=$HOME/opt/dcdn/pop --ram $RAM --pubKey $PUB_KEY --max-disk $DISK --cache-dir $HOME/opt/dcdn/download_cache --enable-80-443
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
            pre_update
            backup_node_info
            add_ports
            if [[ -z "$LOG_VERSION" ]]; then
            echo "Update not found."
            exit 0
            fi
            # Get the current version of the program
            #CURRENT_VERSION=$($HOME/opt/dcdn/pop --version | awk '{print $5}')

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
            pre_update
            journalctl -n 100 -f -u pop -o cat
            break
            ;;

        "AutoUpdate")
        # Check if the update script exists
        pre_update
        if [ ! -f "$HOME/opt/dcdn/update_node.sh" ]; then
        echo "File $HOME/opt/dcdn/update_node.sh does not exist. Creating the update script..."
        backup_node_info
        tg_bot
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
OnBootSec=5min
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
            pre_update
            cd $HOME/opt/dcdn/ && ./pop --gen-referral-route
            cd $HOME
            break
            ;;
        "Points")
            pre_update
            cd $HOME/opt/dcdn/ && ./pop --points
            cd $HOME
            break
            ;;
        "Status")
            pre_update
            cd $HOME/opt/dcdn/ && ./pop --status
            cd $HOME
            break
            ;;
        
        "Change System Requirements")
            pre_update
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
            pre_update

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