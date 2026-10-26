#!/usr/bin/env bash
# scripts/lab5/01-banco-tiendasur.sh — crea el banco de pruebas de índices (migración V004) y lo describe con números
# Uso: bash scripts/lab5/01-banco-tiendasur.sh
set -euo pipefail
source scripts/deployment/env/00-config.sh
MIG_EVID="$EVID_LAB5/spool" MIG_PARTE=01 bash scripts/deployment/env/08-aplicar-migraciones.sh V004__banco_tiendasur
bash scripts/ops/sysdba.sh scripts/lab5/01-perfil-tiendasur.sql "$EVID_LAB5/script/$(ts)_01-perfil-tiendasur.script.log"
bash scripts/ops/sysdba.sh scripts/lab5/01-herramienta-medir.sql "$EVID_LAB5/script/$(ts)_01-herramienta-medir.script.log"
