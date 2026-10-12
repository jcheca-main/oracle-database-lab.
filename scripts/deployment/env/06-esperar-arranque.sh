#!/usr/bin/env bash
# scripts/deployment/env/06-esperar-arranque.sh
set -euo pipefail
source scripts/deployment/env/00-config.sh
FMT='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}'
echo "== Esperando a que $CONT_NAME este healthy (max. 5 min) =="
estado="starting"
for i in $(seq 1 60); do
 estado=$(docker inspect -f "$FMT" "$CONT_NAME")
 echo " intento $i: $estado"
 if [ "$estado" = "healthy" ]; then break; fi
 sleep 5
done
if [ "$estado" != "healthy" ]; then
 echo "AVISO: el contenedor no llego a healthy; revisa el log de abajo"
fi
echo "== Estado final =="
docker ps --filter "name=$CONT_NAME" --format '{{.Names}} {{.Status}}'
echo "== Registro de arranque (docker logs) =="
docker logs "$CONT_NAME" 2>&1
