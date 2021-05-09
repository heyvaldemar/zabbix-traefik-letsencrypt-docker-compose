#!/bin/bash

ZABBIX_CONTAINER=$(docker ps -aqf "name=zabbix_zabbix")
ZABBIX_BACKUPS_CONTAINER=$(docker ps -aqf "name=zabbix_backups")

echo "--> All available database backups:"

for entry in $(docker container exec -it $ZABBIX_BACKUPS_CONTAINER sh -c "ls /srv/zabbix-postgres/backups/")
do
  echo "$entry"
done

echo "--> Copy and paste the backup name from the list above to restore database and press [ENTER]
--> Example: zabbix-postgres-backup-YYYY-MM-DD_hh-mm.gz"
echo -n "--> "

read SELECTED_DATABASE_BACKUP

echo "--> $SELECTED_DATABASE_BACKUP was selected"

echo "--> Stopping service..."
docker stop $ZABBIX_CONTAINER

echo "--> Restoring database..."
docker exec -it $ZABBIX_BACKUPS_CONTAINER sh -c 'PGPASSWORD="$(echo $POSTGRES_PASSWORD)" dropdb -h postgres -p 5432 zabbixdb -U zabbixdbuser \
&& PGPASSWORD="$(echo $POSTGRES_PASSWORD)" createdb -h postgres -p 5432 zabbixdb -U zabbixdbuser \
&& PGPASSWORD="$(echo $POSTGRES_PASSWORD)" gunzip -c /srv/zabbix-postgres/backups/'$SELECTED_DATABASE_BACKUP' | PGPASSWORD=$(echo $POSTGRES_PASSWORD) psql -h postgres -p 5432 zabbixdb -U zabbixdbuser'
echo "--> Database recovery completed..."

echo "--> Starting service..."
docker start $ZABBIX_CONTAINER
