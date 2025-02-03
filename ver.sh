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
            ((PATCH++))  # Збільшуємо версію PATCH
        else
            if [ "$PATCH" -gt 0 ]; then
                ((PATCH--))  # Зменшуємо версію PATCH, якщо вона була збільшена
                LAST_VERSION="v${MAJOR}.${MINOR}.${PATCH}"
            fi
            PATCH=0  # Скидаємо PATCH
            ((MINOR++))  # Переходимо до наступної мінорної версії
            if ! check_version; then
                ((MINOR--))  # Якщо версія не існує, повертаємось до попередньої
                break
            fi
        fi
    done

    echo "$LAST_VERSION"
}

LATEST_VERSION=$(get_latest_version "https://dl.pipecdn.app" "pop" "v0.2.0")
echo "$(echo "$LATEST_VERSION" | sed 's/^v//')"
