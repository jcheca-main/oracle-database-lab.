#!/usr/bin/env bash
# scripts/lab4/10-ciclo-vida-pdb.sh — ejecuta 10-ciclo-vida-pdb.sql y borra la carpeta vacía que deja el DROP PLUGGABLE DATABASE
set -euo pipefail
source scripts/deployment/env/00-config.sh
bash scripts/ops/sysdba.sh scripts/lab4/10-ciclo-vida-pdb.sql "${1:-/dev/null}"
docker exec "$CONT_NAME" bash -c "rmdir $DATA_ROOT/FREE/PDB_LAB4 2>/dev/null && echo 'Carpeta PDB_LAB4 eliminada' || true"
