#!/usr/bin/env bash
# scripts/deployment/env/00-config.sh
# Constantes del proyecto oracle-database-lab. Uso: source scripts/deployment/env/00-config.sh
# NO contiene secretos: las contraseñas viven en config/.env (Lab 4, Parte B).
export CONT_NAME="oralab-26ai"
export VOL_NAME="oralab-26ai-data"
export IMG="container-registry.oracle.com/database/free:latest"
export PORT_DB=1521
export PORT_ORDS=8181          # Lab 4: OBSOLETA. ORDS corre en Linux y escucha en ORDS_PORT (8080); se conserva solo por compatibilidad
export SERVICE_CDB="FREE"
export SERVICE_PDB="FREEPDB1"
export BACKUP_DIR="$(pwd)/backups"
export EVID="docs/bitacora/evidencia"
# Marca de tiempo ISO 8601 en UTC para nombrar la evidencia: $(ts)
ts() { date -u +%Y%m%dT%H%M%SZ; }
# ORDS (Lab 3, Parte M): middleware instalado en Linux, fuera del contenedor de la base
export ORDS_HOME="/opt/oracle/ords"
export ORDS_CONFIG="/etc/ords/config"
export ORDS_LOGS="/var/log/ords"
export ORDS_PORT=8080
# Lab 4: operación del entorno (backup/restauración y evidencia por laboratorio)
export HELPER_IMG="ubuntu:24.04"          # imagen auxiliar con GNU tar para copiar el volumen
export DATA_ROOT="/opt/oracle/oradata"    # punto de montaje del volumen dentro del contenedor
export EVID_LAB4="docs/bitacora/lab4/evidencia"   # evidencia del Lab 4: script/, spool/, config/
export EVID_LAB5="docs/bitacora/lab5/evidencia"   # evidencia del Lab 5: script/, spool/, config/
