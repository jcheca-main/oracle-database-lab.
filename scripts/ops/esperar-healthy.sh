#!/usr/bin/env bash
# scripts/ops/esperar-healthy.sh — sonda de disponibilidad (readiness probe) con límite de tiempo.
# Lista = el CDB y FREEPDB1 están abiertos en READ WRITE. También muestra la salud que informa Docker.
# Uso: bash scripts/ops/esperar-healthy.sh [segundos_max, por defecto 600]
set -euo pipefail
source scripts/deployment/env/00-config.sh
MAX="${1:-600}"
FMT='{{if .State.Health}}{{.State.Health.Status}}{{else}}sin-healthcheck{{end}}'
SONDA="SELECT d.open_mode || '/' || p.open_mode FROM v\$database d, v\$pdbs p WHERE p.name = '$SERVICE_PDB';"
for ((t = 0; t <= MAX; t += 10)); do
  salud=$(docker inspect -f "$FMT" "$CONT_NAME")
  modo=$(printf 'WHENEVER SQLERROR EXIT 1\nSET HEADING OFF FEEDBACK OFF PAGESIZE 0\n%s\nEXIT\n' "$SONDA" \
         | docker exec -i "$CONT_NAME" sqlplus -s -L / as sysdba 2> /dev/null | tr -d '[:space:]') || modo=""
  case "$modo" in *ORA-*|*ERROR*) modo="" ;; esac
  echo "  t=${t}s  docker=$salud  cdb/pdb=${modo:-no-disponible}"
  if [ "$modo" = "READWRITE/READWRITE" ]; then exit 0; fi
  sleep 10
done
echo "AVISO: la base no quedó abierta en ${MAX}s. Revisa: docker logs --tail 50 $CONT_NAME" >&2
exit 1
