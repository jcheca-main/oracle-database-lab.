#!/usr/bin/env bash
# scripts/ops/restaurar-estado.sh — devuelve el entorno al estado de una copia de backup-estado.sh
# Uso: bash scripts/ops/restaurar-estado.sh <carpeta-de-la-copia> [--si]
set -euo pipefail
source scripts/deployment/env/00-config.sh
docker info > /dev/null 2>&1 || { echo "ERROR: Docker no responde (¿está arrancado Docker Desktop o el servicio docker?). No se ha tocado nada." >&2; exit 1; }

ORIGEN="${1:?Uso: restaurar-estado.sh <carpeta en backups/> [--si]}"
ORIGEN="$(cd "$ORIGEN" && pwd)"          # ruta absoluta: docker -v la exige
CONFIRMAR="${2:-}"

echo "== 1. Integridad de la copia (SHA-256) =="
(cd "$ORIGEN" && sha256sum --check --quiet SHA256SUMS)
echo "OK: la copia está íntegra"
cat "$ORIGEN/manifiesto.txt"

echo "== 2. Confirmación =="
if [ "$CONFIRMAR" != "--si" ]; then
  echo "Se BORRARÁ el contenido actual de $VOL_NAME y se sustituirá por esta copia."
  read -r -p "Escribe el nombre del volumen para confirmar: " respuesta
  [ "$respuesta" = "$VOL_NAME" ] || { echo "Cancelado: no se ha tocado nada"; exit 1; }
fi

echo "== 3. Parada de la base de datos y del contenedor =="
RECREAR="no"
if docker inspect "$CONT_NAME" > /dev/null 2>&1; then
  if [ "$(docker inspect -f '{{.State.Running}}' "$CONT_NAME")" = "true" ]; then
    echo "SHUTDOWN IMMEDIATE" | docker exec -i "$CONT_NAME" sqlplus -s -L / as sysdba || true
    docker stop -t 120 "$CONT_NAME" > /dev/null
  fi
else
  echo "El contenedor no existe: se recreará con 05-crear-contenedor.sh"
  RECREAR="si"
fi

echo "== 4. Restauración del volumen =="
docker volume create "$VOL_NAME" > /dev/null
docker run --rm -v "$VOL_NAME":/destino -v "$ORIGEN":/origen:ro "$HELPER_IMG" \
  sh -c 'find /destino -mindepth 1 -delete && tar --numeric-owner -xzpf /origen/volumen.tar.gz -C /destino'

if [ "$RECREAR" = "si" ]; then
  bash scripts/deployment/env/05-crear-contenedor.sh
  docker stop -t 120 "$CONT_NAME" > /dev/null
fi

echo "== 5. Archivos fuera del volumen =="
if [ -s "$ORIGEN/extras/mapa.txt" ]; then
  while IFS='|' read -r tarfile ruta; do
    gunzip -c "$ORIGEN/extras/$tarfile" | docker cp -a - "$CONT_NAME:$(dirname "$ruta")"
    echo "  restaurado $ruta"
  done < "$ORIGEN/extras/mapa.txt"
else
  echo "  ninguno"
fi

echo "== 6. Arranque y verificación =="
docker start "$CONT_NAME" > /dev/null
bash scripts/ops/esperar-healthy.sh
docker exec -i "$CONT_NAME" sqlplus -s -L / as sysdba <<'SQL'
SET LINESIZE 160 PAGESIZE 50 FEEDBACK OFF
COLUMN name FORMAT A12
SELECT instance_name, status FROM v$instance;
SELECT name, open_mode, log_mode FROM v$database;
SELECT name, open_mode FROM v$pdbs;
SELECT owner, COUNT(*) AS tablas FROM cdb_tables
 WHERE owner LIKE 'ADMIN\_%' ESCAPE '\' GROUP BY owner ORDER BY owner;
EXIT
SQL
echo "== Restauración terminada: estado de «$(grep '^etiqueta=' "$ORIGEN/manifiesto.txt" | cut -d= -f2)» =="
