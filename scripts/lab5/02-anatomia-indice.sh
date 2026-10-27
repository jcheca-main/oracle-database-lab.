#!/usr/bin/env bash
# scripts/lab5/02-anatomia-indice.sh — anatomía de un índice: diccionario, INDEX_STATS, volcado de raíz y hoja, y radiografía de las hojas
# Uso: bash scripts/lab5/02-anatomia-indice.sh
set -euo pipefail
source scripts/deployment/env/00-config.sh
TS=$(ts)
mkdir -p "$EVID_LAB5/script" "$EVID_LAB5/config"
bash scripts/ops/sysdba.sh scripts/lab5/02-anatomia-indice.sql "$EVID_LAB5/script/${TS}_02-anatomia-indice.script.log"
for IDX in PK_PEDIDO IX_PED_CLIENTE; do
  bash scripts/ops/grafico-indice.sh TIENDASUR "$IDX" "$EVID_LAB5/script/${TS}_02-grafico-${IDX}.script.log"
done
TRAZA=$(docker exec "$CONT_NAME" bash -c 'ls -t /opt/oracle/diag/rdbms/free/FREE/trace/*lab5_indice*.trc | head -1')
docker cp "$CONT_NAME:$TRAZA" "$EVID_LAB5/config/${TS}_02-volcado-indice.trc.txt"
echo "Traza del treedump y de los volcados copiada a $EVID_LAB5/config/${TS}_02-volcado-indice.trc.txt"
