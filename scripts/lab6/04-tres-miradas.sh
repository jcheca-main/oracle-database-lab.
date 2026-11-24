#!/usr/bin/env bash
# scripts/lab6/04-tres-miradas.sh — «lo que no ves puede ser un límite de tu vista, no la ausencia del objeto»
# Uso: bash scripts/lab6/04-tres-miradas.sh | tee "$EVID_LAB6/script/$(ts)_04-tres-miradas.script.log"
set -uo pipefail
source scripts/deployment/env/00-config.sh
source scripts/ops/cabecera.sh "$(basename "$0" .sh)" || exit 2   # Lab 6: cabecera de evidencia (alumno, hora, contenedor, SCN)
echo "################ Mirada 1 · C##OPS_RO en CDB\$ROOT (con CONTAINER_DATA = ALL) ################"
bash scripts/ops/ro.sh scripts/lab6/04-tres-miradas.sql
echo "################ Mirada 2 · C##OPS_RO entrando por el servicio freepdb1 ################"
bash scripts/ops/ro.sh scripts/lab6/04-tres-miradas.sql freepdb1
echo "################ Mirada 3 · APP_ACADEMIA por academia_app (cuenta de aplicación, sin catálogo) ################"
bash scripts/ops/app.sh scripts/lab6/04-tres-miradas.sql
