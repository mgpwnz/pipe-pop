#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------
# POP Cache Node Update Script (версия можно указать аргументом)
# -------------------------------------------------------------
# Останавливает службу popcache, делает бэкап старого бинарника,
# скачивает выбранную версию (по умолчанию 0.3.1), заменяет
# /opt/popcache/pop, устанавливает права и перезапускает службу.
# -------------------------------------------------------------

# Если передан первый аргумент, используем его как версию, иначе дефолт
if [[ $# -ge 1 ]]; then
  NEW_VERSION="$1"
else
  NEW_VERSION="0.3.1"
fi

ARCHIVE_URL="https://download.pipe.network/static/pop-v${NEW_VERSION}-linux-x64.tar.gz"

# Пути
CONFIG_DIR="/opt/popcache"
BINARY_PATH="${CONFIG_DIR}/pop"
SERVICE_NAME="popcache"
TMP_DIR="$(mktemp -d)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="${CONFIG_DIR}/backup_${TIMESTAMP}"
ARCHIVE_TMP="/tmp/pop-v${NEW_VERSION}-linux-x64.tar.gz"

echo "===== Обновление POP Cache Node до версии ${NEW_VERSION} ====="

# Проверка запуска от root
if [[ $EUID -ne 0 ]]; then
  echo "Ошибка: скрипт должен быть запущен от root." >&2
  exit 1
fi

# 1. Остановить службу
echo -e "\n1) Останавливаем службу ${SERVICE_NAME}..."
if systemctl is-active --quiet "${SERVICE_NAME}"; then
  systemctl stop "${SERVICE_NAME}"
  echo "   Служба ${SERVICE_NAME} остановлена."
else
  echo "   Служба ${SERVICE_NAME} уже не запущена."
fi

# 2. Создать резервную копию старого бинарника
if [[ -f "${BINARY_PATH}" ]]; then
  echo -e "\n2) Создаём резервную копию старого бинарника..."
  mkdir -p "${BACKUP_DIR}"
  cp "${BINARY_PATH}" "${BACKUP_DIR}/pop-v-backup-${TIMESTAMP}"
  echo "   Старый бинарник сохранён в ${BACKUP_DIR}/pop-v-backup-${TIMESTAMP}"
else
  echo "   Внимание: не найден бинарник ${BINARY_PATH}, пропускаем бэкап."
fi

# 3. Скачиваем новую версию
echo -e "\n3) Скачиваем pop-v${NEW_VERSION}..."
curl -sSL "${ARCHIVE_URL}" -o "${ARCHIVE_TMP}"
echo "   Скачано: ${ARCHIVE_TMP}"

# 4. Распаковываем в временную папку
echo -e "\n4) Распаковываем архив..."
tar -xzf "${ARCHIVE_TMP}" -C "${TMP_DIR}"
NEW_BINARY_SRC="$(find "${TMP_DIR}" -type f -name pop -print -quit)"
if [[ -z "${NEW_BINARY_SRC}" ]]; then
  echo "Ошибка: не найден файл 'pop' внутри архива." >&2
  rm -rf "${TMP_DIR}" "${ARCHIVE_TMP}"
  exit 1
fi

# 5. Заменяем старый бинарник
echo -e "\n5) Заменяем бинарник в ${BINARY_PATH}..."
mv "${NEW_BINARY_SRC}" "${BINARY_PATH}"
chmod +x "${BINARY_PATH}"
chown popcache:popcache "${BINARY_PATH}"
echo "   Новый бинарник установлен."

# 6. Пробуем назначить права для bind на низкие порты
echo -e "\n6) Пробуем установить cap_net_bind_service на бинарник..."
if setcap 'cap_net_bind_service=+ep' "${BINARY_PATH}"; then
  echo "   setcap выполнен успешно."
else
  echo "   setcap завершился с ошибкой, проверьте конфигурацию authbind по необходимости."
fi

# 7. Чистим временные файлы
echo -e "\n7) Удаляем временные файлы..."
rm -rf "${TMP_DIR}" "${ARCHIVE_TMP}"
echo "   Временные файлы удалены."

# 8. Запускаем службу заново
echo -e "\n8) Перезапускаем службу ${SERVICE_NAME}..."
systemctl daemon-reload
systemctl start "${SERVICE_NAME}"
sleep 1
if systemctl is-active --quiet "${SERVICE_NAME}"; then
  echo "   Служба ${SERVICE_NAME} успешно запущена (версия $( "${BINARY_PATH}" --version || echo "не удалось проверить версию") )."
else
  echo "   Внимание: служба ${SERVICE_NAME} не запустилась, проверьте логи: sudo journalctl -u ${SERVICE_NAME} -n 50" >&2
  exit 1
fi

echo -e "\n===== Обновление до версии ${NEW_VERSION} завершено. ====="
