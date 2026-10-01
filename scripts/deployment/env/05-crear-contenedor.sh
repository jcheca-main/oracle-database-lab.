#!/usr/bin/env bash
# scripts/deployment/env/05-crear-contenedor.sh
set -euo pipefail
source scripts/deployment/env/00-config.sh
set -a; source config/.env; set +a
# Idempotencia: si el contenedor ya existe, no se intenta crear otra vez.
if docker ps -a --format '{{.Names}}' | grep -qx "$CONT_NAME"; then
 echo "El contenedor $CONT_NAME ya existe; no se crea de nuevo."
 docker ps -a --filter "name=$CONT_NAME"
 exit 0
fi
docker run -d \
 --name "$CONT_NAME" \
 -p "$PORT_DB":1521 \
 -p "$PORT_ORDS":8181 \
 -e ORACLE_PWD="$ORACLE_PWD" \
 -e APP_USER=alumno \
 -e APP_USER_PASSWORD="$APP_USER_PWD" \
 -v "$VOL_NAME":/opt/oracle/oradata \
 "$IMG"
echo "Contenedor $CONT_NAME creado."
docker ps --filter "name=$CONT_NAME"
