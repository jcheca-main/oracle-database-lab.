#!/usr/bin/env bash
# scripts/deployment/env/00-config.sh
# Constantes del proyecto oracle-database-lab. Uso: source scripts/deployment/env/00-config.sh
# NO contiene secretos: las contraseñas viven en config/.env (Parte D).
export CONT_NAME="oralab-26ai"
export VOL_NAME="oralab-26ai-data"
export IMG="container-registry.oracle.com/database/free:latest"
export PORT_DB=1521
export PORT_ORDS=8181
export SERVICE_CDB="FREE"
export SERVICE_PDB="FREEPDB1"
export BACKUP_DIR="$(pwd)/backups"
export EVID="docs/bitacora/evidencia"
# Marca de tiempo ISO 8601 en UTC para nombrar la evidencia: $(ts)
ts() { date -u +%Y%m%dT%H%M%SZ; }
