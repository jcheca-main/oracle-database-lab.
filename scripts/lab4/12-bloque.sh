#!/usr/bin/env bash
# scripts/lab4/12-bloque.sh — ejecuta 12-bloque.sql y copia la traza completa del volcado del bloque a la evidencia
# Uso: bash scripts/lab4/12-bloque.sh
set -euo pipefail
source scripts/deployment/env/00-config.sh
TS=$(ts)
mkdir -p "$EVID_LAB4/script" "$EVID_LAB4/config"
bash scripts/ops/sysdba.sh scripts/lab4/12-bloque.sql "$EVID_LAB4/script/${TS}_12-bloque.script.log"
TRAZA=$(docker exec "$CONT_NAME" bash -c 'ls -t /opt/oracle/diag/rdbms/free/FREE/trace/*lab4_bloque*.trc | head -1')
docker cp "$CONT_NAME:$TRAZA" "$EVID_LAB4/config/${TS}_12-volcado-bloque.trc.txt"
echo "Traza completa copiada a $EVID_LAB4/config/${TS}_12-volcado-bloque.trc.txt ($(wc -l < "$EVID_LAB4/config/${TS}_12-volcado-bloque.trc.txt") líneas)"
