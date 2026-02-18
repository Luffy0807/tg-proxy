#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

: "${FRONT_HOST:=cloudflare.com}"
: "${HOST_PORT:=8443}"
: "${HOST_BIND_IP:=0.0.0.0}"
: "${TOLERATE_TIME_SKEWNESS:=12h0m0s}"

detect_public_host() {
  # если задан домен/ип вручную в окружении или .env
  if [[ -n "${PUBLIC_HOST:-}" ]]; then
    echo "$PUBLIC_HOST"
    return 0
  fi

  # пробуем внешние сервисы (быстро, без зависимостей)
  local ip=""
  for u in "https://api.ipify.org" "https://icanhazip.com" "https://ifconfig.me/ip"; do
    ip="$(curl -fsS --max-time 3 "$u" 2>/dev/null | tr -d '\r\n ' || true)"
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      echo "$ip"
      return 0
    fi
  done

  # fallback: src-адрес по маршруту (может быть не паблик, но лучше чем ничего)
  ip="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true)"
  if [[ -n "$ip" ]]; then
    echo "$ip"
    return 0
  fi

  echo "UNKNOWN"
  return 0
}

make_links() {
  local host="$1"
  local port="$2"
  local secret="$3"

  echo "tg://proxy?server=${host}&port=${port}&secret=${secret}"
  echo "https://t.me/proxy?server=${host}&port=${port}&secret=${secret}"
}

# Создаём .env один раз, дальше руками не трогаем
if [[ ! -f .env ]]; then
  MTG_SECRET="$(docker run --rm nineseconds/mtg:2 generate-secret --hex "$FRONT_HOST" | tail -n 1)"
  cat > .env <<ENV
FRONT_HOST=$FRONT_HOST
HOST_PORT=$HOST_PORT
HOST_BIND_IP=$HOST_BIND_IP
TOLERATE_TIME_SKEWNESS=$TOLERATE_TIME_SKEWNESS
# PUBLIC_HOST можно задать вручную (домен или ip). Если пусто - определим автоматически.
PUBLIC_HOST=
MTG_SECRET=$MTG_SECRET
ENV
  chmod 600 .env
fi

# Загружаем переменные
set -a
source ./.env
set +a

# Проверим, что порт свободен (кроме случаев, когда его держит уже наш контейнер)
if ss -lntp | grep -qE "[:.]${HOST_PORT}[[:space:]]" ; then
  if ! docker ps --format '{{.Names}} {{.Ports}}' | grep -q "mtg-proxy" ; then
    echo "ERROR: host port ${HOST_PORT} уже занят (и это не mtg-proxy). Меняй HOST_PORT в .env."
    exit 1
  fi
fi

# Рендерим конфиг из шаблона
envsubst < config.toml.tpl > config.toml
chmod 600 config.toml

docker compose -f compose.yml pull
docker compose -f compose.yml up -d
docker compose -f compose.yml ps

# Формируем access.txt (секрет внутри, поэтому 600)
PUB="$(detect_public_host)"
{
  echo "Generated: $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
  echo "Server: ${PUB}"
  echo "Port: ${HOST_PORT}"
  echo
  echo "Links:"
  make_links "$PUB" "$HOST_PORT" "$MTG_SECRET"
} > access.txt
chmod 600 access.txt

# Печатаем ссылку только если это ручной запуск в терминале (не systemd/CI)
if [[ -t 1 ]]; then
  echo
  echo "MTProto Proxy links (saved to /opt/mtg-deploy/access.txt):"
  tail -n 3 access.txt
  echo
fi
