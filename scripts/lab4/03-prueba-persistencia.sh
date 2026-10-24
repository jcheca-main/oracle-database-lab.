#!/usr/bin/env bash
# scripts/lab4/03-prueba-persistencia.sh — la prueba de fuego: borrar el CONTENEDOR y comprobar que la BASE sigue
# Se recrea con 05-crear-contenedor.sh versión 2 (sin el puerto 8181 y sin contraseñas).
# Si los datafiles estuvieran fuera del volumen, aquí se perderían: por eso se ejecuta DESPUÉS de 03-reubicar
# y DESPUÉS del backup de la Parte A.
set -euo pipefail
source scripts/deployment/env/00-config.sh
# Antes de borrar nada: la imagen con la que se va a recrear TIENE que estar disponible.
# Si no (sin «docker login container-registry.oracle.com» o sin red), el contenedor se borraría y no se podría recrear.
if ! docker image inspect "$IMG" > /dev/null 2>&1; then
  echo "La imagen $IMG no está en local: se descarga ANTES de borrar el contenedor"
  docker pull "$IMG" || { echo "ERROR: no se puede descargar $IMG (¿docker login container-registry.oracle.com?). No se ha tocado nada."; exit 1; }
fi
echo "== 1. ANTES: entornos de negocio =="
bash scripts/ops/sysdba.sh scripts/lab4/03-verificar-negocio.sql
echo "== 2. Parada limpia (SHUTDOWN IMMEDIATE) y borrado del contenedor; el volumen $VOL_NAME se conserva =="
printf 'SHUTDOWN IMMEDIATE\nEXIT\n' | docker exec -i "$CONT_NAME" sqlplus -s -L / as sysdba
docker stop -t 120 "$CONT_NAME" >/dev/null
docker rm "$CONT_NAME"
docker volume ls --filter "name=$VOL_NAME"
echo "== 3. Recrear el contenedor con la definición corregida =="
bash scripts/deployment/env/05-crear-contenedor.sh
bash scripts/ops/esperar-healthy.sh
echo "== 4. DESPUÉS: mismos entornos, mismos datos =="
bash scripts/ops/sysdba.sh scripts/lab4/03-verificar-negocio.sql
echo "== 5. Puertos publicados ahora (ya no aparece 8181) =="
docker port "$CONT_NAME"
