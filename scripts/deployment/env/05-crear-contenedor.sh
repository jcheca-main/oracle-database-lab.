#!/usr/bin/env bash
# scripts/deployment/env/05-crear-contenedor.sh — versión 2 (Lab 4)
# Cambios frente al Lab 3:
#  - Ya no publica 8181: ORDS se instaló en Linux (Parte M del Lab 3) y escucha en $ORDS_PORT (8080),
#    fuera del contenedor; dentro del contenedor nadie escuchaba en 8181.
#  - Si el volumen YA contiene una base de datos, no pasa ninguna contraseña: la imagen solo la usa
#    al crear la base la primera vez. Menos secretos en `docker inspect` = menos superficie de ataque.
set -euo pipefail
source scripts/deployment/env/00-config.sh
if docker ps -a --format '{{.Names}}' | grep -x "$CONT_NAME" > /dev/null; then
  echo "El contenedor $CONT_NAME ya existe; no se crea de nuevo."
  docker ps -a --filter "name=$CONT_NAME"
  exit 0
fi
if docker run --rm -v "$VOL_NAME":/datos "$HELPER_IMG" test -d /datos/FREE 2>/dev/null; then
  echo "El volumen $VOL_NAME ya contiene la base FREE: se reutiliza (sin contraseñas)."
  docker run -d --name "$CONT_NAME" -p "$PORT_DB":1521 \
    -v "$VOL_NAME":/opt/oracle/oradata "$IMG"
else
  echo "Volumen vacío: primera creación de la base."
  set -a; source config/.env; set +a
  docker run -d --name "$CONT_NAME" -p "$PORT_DB":1521 \
    -e ORACLE_PWD="$ORACLE_PWD" \
    -v "$VOL_NAME":/opt/oracle/oradata "$IMG"
fi
echo "Contenedor $CONT_NAME creado."
docker ps --filter "name=$CONT_NAME"
