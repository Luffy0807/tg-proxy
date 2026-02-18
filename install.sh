#!/usr/bin/env bash
set -euo pipefail

# ---------- настройки по умолчанию ----------
: "${REPO_RAW_BASE:=https://raw.githubusercontent.com/Luffy0807/tg-proxy/main}"
: "${APP_DIR:=$HOME/tg-proxy}"
: "${FRONT_HOST:=cloudflare.com}"
: "${HOST_PORT:=8443}"          # 443 обычно занят 
: "${HOST_BIND_IP:=0.0.0.0}"
: "${TOLERATE_TIME_SKEWNESS:=12h0m0s}"


command -v docker >/dev/null || { echo "ERROR: docker не найден"; exit 1; }
docker ps >/dev/null 2>&1 || { echo "ERROR: нет доступа к docker. Нужна группа docker или rootless docker."; exit 1; }

mkdir -p "$APP_DIR"
cd "$APP_DIR"
chmod 700 "$APP_DIR"

curl -fsSLo compose.yml       "$REPO_RAW_BASE/compose.yml"
curl -fsSLo config.toml.tpl   "$REPO_RAW_BASE/config.toml.tpl"

# ---------- создать .env  ----------
if [[ ! -f .env ]]; then
  MTG_SECRET="$(docker run --rm nineseconds/mtg:2 generate-secret --hex "$FRONT_HOST" | tail -n 1)"
  cat > .env <<ENV
FRONT_HOST=$FRONT_HOST
HOST_PORT=$HOST_PORT
HOST_BIND_IP=$HOST_BIND_IP
TOLERATE_TIME_SKEWNESS=$TOLERATE_TIME_SKEWNESS
MTG_SECRET=$MTG_SECRET
ENV
  chmod 600 .env
fi

# ---------- загрузить env ----------
set -a
# shellcheck disable=SC1091
source ./.env
set +a

# ----------  порт ----------
if ss -lnt 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${HOST_PORT}$" ; then
  echo "ERROR: порт ${HOST_PORT} уже занят. Поменяй HOST_PORT в $APP_DIR/.env и повтори."
  exit 1
fi

# ----------  config.toml  ----------
# (чтобы не требовать gettext-base)
tmp="$(mktemp)"
cp config.toml.tpl "$tmp"

# простая подстановка переменных
sed -i \
  -e "s|\${MTG_SECRET}|${MTG_SECRET}|g" \
  -e "s|\${TOLERATE_TIME_SKEWNESS}|${TOLERATE_TIME_SKEWNESS}|g" \
  "$tmp"

mv "$tmp" config.toml
chmod 600 config.toml

# ---------- поднять ----------
docker compose -f compose.yml --env-file .env pull
docker compose -f compose.yml --env-file .env up -d
docker compose -f compose.yml ps

# ---------- напечатать ссылку  ----------
EXT_IP="$(curl -4fsS https://api.ipify.org 2>/dev/null || true)"
if [[ -z "$EXT_IP" ]]; then
  EXT_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk "/src/ {print \$7; exit}" || true)"
fi

echo
echo "WARNING: ссылка содержит SECRET"
if [[ -n "$EXT_IP" ]]; then
  echo "https://t.me/proxy?server=${EXT_IP}&port=${HOST_PORT}&secret=${MTG_SECRET}"
else
  echo "Не смог определить IP автоматически."
  echo "Собери вручную: https://t.me/proxy?server=<YOUR_IP>&port=${HOST_PORT}&secret=${MTG_SECRET}"
fi

# на всякий случай
umask 077
{
  echo "FRONT_HOST=$FRONT_HOST"
  echo "HOST_PORT=$HOST_PORT"
  echo "MTG_LINK=https://t.me/proxy?server=${EXT_IP:-<YOUR_IP>}&port=${HOST_PORT}&secret=${MTG_SECRET}"
} > mtg-link.txt
chmod 600 mtg-link.txt
