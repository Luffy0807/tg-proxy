# MTG proxy deployment (Debian 12, Docker Compose, GitOps)

## First run on server
./deploy.sh

## Change port (because 443 is busy)
Edit .env:
HOST_PORT=8443

## Get access URL (contains secret, don't paste to logs)
docker exec mtg-proxy /mtg access /config.toml
