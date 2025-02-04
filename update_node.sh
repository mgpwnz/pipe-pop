#!/bin/bash

# Download the latest available version
LATEST_VERSION=$(. <(wget -qO- https://raw.githubusercontent.com/mgpwnz/pipe-pop/refs/heads/main/ver.sh))

# Get the current version of the program
CURRENT_VERSION=$($HOME/opt/dcdn/pop --version | awk '{print \$5}')

# Print the current and latest version for verification
echo "Current version: $CURRENT_VERSION"
echo "Latest available version: $LATEST_VERSION"

# Comparing versions
if [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
    echo "Update available! Updating version..."

    # Downloading the new version as a temporary file
    download_pop() {
        local max_retries=5
        local attempt=0
        local dest_dir="$HOME/opt/dcdn"
        local temp_file="$dest_dir/pop.tmp"

        sudo mkdir -p "$dest_dir/download_cache"

        while (( attempt < max_retries )); do
            sudo wget -O "$temp_file" "https://dl.pipecdn.app/$LATEST_VERSION/pop"
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

    download_pop

    # Stopping the service after successful download
    sudo systemctl stop pop

    # Replacing the old version with the new one
    mv "$HOME/opt/dcdn/pop.tmp" "$HOME/opt/dcdn/pop"
    sudo chmod +x "$HOME/opt/dcdn/pop"
    sudo rm -rf "$HOME/opt/dcdn/download_cache"

    # Update the symbolic link
    sudo rm -f /usr/local/bin/pop
    sudo ln -s $HOME/opt/dcdn/pop /usr/local/bin/pop

    # Restart the service
    sudo systemctl start pop

    echo "Update completed successfully."
else
    echo "You are already using the latest version: $CURRENT_VERSION"
fi
