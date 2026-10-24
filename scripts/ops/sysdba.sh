#!/usr/bin/env bash
# scripts/ops/sysdba.sh — ejecuta un .sql como SYSDBA con autenticación del sistema operativo
# (sin contraseña) dentro del contenedor, y guarda la salida como evidencia.
# Uso: bash scripts/ops/sysdba.sh <archivo.sql> [archivo-de-evidencia]
set -euo pipefail
source scripts/deployment/env/00-config.sh
SQL_FILE="${1:?Uso: sysdba.sh <archivo.sql> [evidencia]}"
LOG="${2:-/dev/null}"
[ -f "$SQL_FILE" ] || { echo "No existe $SQL_FILE" >&2; exit 2; }
[ "$LOG" = /dev/null ] || mkdir -p "$(dirname "$LOG")"   # la carpeta de evidencias puede no existir aún
docker exec -i "$CONT_NAME" sqlplus -s -L / as sysdba < "$SQL_FILE" | tee "$LOG"
