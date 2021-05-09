# Zabbix with Let's Encrypt in a Docker Compose

Install the Docker Engine by following the official guide: https://docs.docker.com/engine/install/

Install the Docker Compose by following the official guide: https://docs.docker.com/compose/install/

Run `zabbix-restore-database.sh` to restore database if needed.

Deploy Zabbix server with a Docker Compose using the command:

`docker-compose -f zabbix-traefik-letsencrypt-docker-compose.yml -p zabbix up -d`
