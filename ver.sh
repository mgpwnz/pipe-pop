#!/bin/bash

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
        local HTTP_CODE=$(curl -s --connect-timeout 5 -o /dev/null -w "%{http_code}" -I "$URL")

        if [ "$HTTP_CODE" -eq 200 ]; then
            LAST_VERSION="${VERSION#v}"  
            return 0
        else
            return 1
        fi
    }

    local MAX_MINOR=20
    local MAX_PATCH=50

    while [ "$MINOR" -lt "$MAX_MINOR" ]; do
        local FOUND_VERSION=false

        for ((PATCH=0; PATCH<MAX_PATCH; PATCH++)); do
            if check_version; then
                FOUND_VERSION=true
            else
                break
            fi
        done

        if ! $FOUND_VERSION; then
            break
        fi

        ((MINOR++))
    done

    echo "$LAST_VERSION"
}

LATEST_VERSION=$(get_latest_version "https://dl.pipecdn.app" "pop" "v0.2.0")
echo "$LATEST_VERSION"
