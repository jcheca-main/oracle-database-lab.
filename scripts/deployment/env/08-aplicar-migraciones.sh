#!/usr/bin/env bash
# scripts/deployment/env/08-aplicar-migraciones.sh
# Aplica V000 y V001 en orden; deja una evidencia por migracion.
set -euo pipefail
source scripts/deployment/env/00-config.sh
set -a; source config/.env; set +a
CONN="sys/$ORACLE_PWD@localhost:1521/$SERVICE_PDB"
for MIG in V000__setup_entornos_negocio V001__create_esquemas_negocio; do
 echo ">> Aplicando $MIG"
 LOG="$EVID/spool/$(ts)_08-$MIG.spool.log"
 if ! docker exec -i "$CONT_NAME" sqlplus -s "$CONN" as sysdba \
 < "database/migrations/$MIG.sql" | tee "$LOG"; then
 echo "ERROR en $MIG: revisa $LOG antes de continuar"
 exit 1
 fi
done
echo ">> Migraciones aplicadas. Evidencias en $EVID/spool/"
