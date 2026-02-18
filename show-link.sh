#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  echo "ERROR: .env not found. Run ./deploy.sh first."
  exit 1
fi

set -a
source ./.env
set +a

if [[ -f access.txt ]]; then
  echo "MTProto Proxy links:"
  tail -n 3 access.txt
  exit 0
fi

echo "ERROR: access.txt not found. Run ./deploy.sh first."
exit 1
