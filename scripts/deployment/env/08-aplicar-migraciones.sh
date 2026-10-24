#!/usr/bin/env bash
# scripts/deployment/env/08-aplicar-migraciones.sh — versión 2 (Lab 4)
# Aplica las migraciones indicadas, en orden, como SYSDBA con autenticación del SO (sin contraseña).
# Cambios frente al Lab 3: ya no pasa "sys/<contraseña>@..." en la línea de comandos (se veía con ps
# y en el historial) y recibe las migraciones como argumentos, así sirve para V002, V003 y siguientes.
# Uso: bash scripts/deployment/env/08-aplicar-migraciones.sh V002__datos_demo_academia [V003__...]
# Lab 5: MIG_EVID y MIG_PARTE cambian la carpeta y el número de la evidencia, p. ej.
#   MIG_EVID=docs/bitacora/lab5/evidencia/spool MIG_PARTE=01 bash scripts/deployment/env/08-aplicar-migraciones.sh V004__banco_tiendasur
set -euo pipefail
source scripts/deployment/env/00-config.sh
[ $# -ge 1 ] || { echo "Uso: $0 <migración> [migración...]  (nombre sin .sql)"; exit 2; }
DEST="${MIG_EVID:-docs/bitacora/lab4/evidencia/spool}"
mkdir -p "$DEST"
for MIG in "$@"; do
  FILE="database/migrations/$MIG.sql"
  [ -f "$FILE" ] || { echo "ERROR: no existe $FILE"; exit 2; }
  LOG="$DEST/$(ts)_${MIG_PARTE:-04}-$MIG.spool.log"
  echo ">> Aplicando $MIG"
  if ! docker exec -i "$CONT_NAME" sqlplus -s -L / as sysdba < "$FILE" | tee "$LOG"; then
    echo "ERROR en $MIG: revisa $LOG antes de continuar"
    exit 1
  fi
done
echo ">> Migraciones aplicadas. Evidencias en $DEST/"
