#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SQL_FILE="$SCRIPT_DIR/../sql/init.sql"

echo "MySQL schema setup boshlandi..."

run_with_sudo_mysql() {
  echo "sudo orqali mysql ishga tushirilmoqda..."
  sudo -v
  sudo mysql < "$SQL_FILE"
}

run_with_admin_credentials() {
  local admin_user="$1"
  local admin_password="$2"
  mysql -u "$admin_user" -p"$admin_password" < "$SQL_FILE"
}

# 1) If explicit admin credentials are provided, use them first.
if [[ -n "${MYSQL_ADMIN_USER:-}" && -n "${MYSQL_ADMIN_PASSWORD:-}" ]]; then
  echo "MYSQL_ADMIN_USER/MYSQL_ADMIN_PASSWORD orqali ulanilmoqda..."
  run_with_admin_credentials "$MYSQL_ADMIN_USER" "$MYSQL_ADMIN_PASSWORD"
  echo "Done: bekgram_local database va bekgram_app user yaratildi."
  exit 0
fi

# 2) Try sudo mysql (common on Debian/Kali with unix_socket auth).
if command -v sudo >/dev/null 2>&1; then
  if run_with_sudo_mysql; then
    echo "Done: bekgram_local database va bekgram_app user yaratildi."
    exit 0
  fi
fi

# 3) Fallback: prompt for an admin account.
echo "Avtomatik usul ishlamadi."
echo "MySQL admin login bilan davom etamiz (root yoki boshqa admin user)."
read -r -p "MySQL admin user: " ADMIN_USER
read -r -s -p "MySQL admin password: " ADMIN_PASSWORD
echo

run_with_admin_credentials "$ADMIN_USER" "$ADMIN_PASSWORD"
echo "Done: bekgram_local database va bekgram_app user yaratildi."
