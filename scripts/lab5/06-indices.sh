#!/usr/bin/env bash
# scripts/lab5/06-indices.sh — Q16 de principio a fin: medir el coste de escribir hoy, con la propuesta del compañero y con la nuestra (V005)
# Uso: bash scripts/lab5/06-indices.sh
set -euo pipefail
source scripts/deployment/env/00-config.sh
TS=$(ts)
mkdir -p "$EVID_LAB5/script" "$EVID_LAB5/spool"
LOG="$EVID_LAB5/script/${TS}_06-indices.script.log"
medir() { { echo "DEFINE escenario = '$1'"; cat scripts/lab5/06-medir-dml.sql; } | docker exec -i "$CONT_NAME" sqlplus -s -L / as sysdba | tee -a "$LOG"; }
# ¿Ya se aplicó V005 en una ejecución anterior? (V005 retira IX_PED_CLIENTE). Entonces la propuesta del compañero chocaría con
# los índices de V005 (IX_PED_CP): solo se vuelve a medir el escenario final.
QUEDA=$(printf "SET HEADING OFF FEEDBACK OFF PAGESIZE 0\nALTER SESSION SET CONTAINER = FREEPDB1;\nSELECT COUNT(*) FROM dba_indexes WHERE owner = 'TIENDASUR' AND index_name = 'IX_PED_CLIENTE';\nEXIT\n" \
        | docker exec -i "$CONT_NAME" sqlplus -s -L / as sysdba | tr -dc '0-9')
if [ "$QUEDA" = "0" ]; then
  echo "V005 ya está aplicada: solo se mide el escenario V005 (para repetir el experimento completo, restaura lab4-final)" | tee -a "$LOG"
  medir "V005"
  exit 0
fi
medir "hoy"
bash scripts/ops/sysdba.sh scripts/lab5/06-propuesta-companero.sql | tee -a "$LOG"
medir "compañero"
bash scripts/ops/sysdba.sh scripts/lab5/06-protocolo.sql | tee -a "$LOG"
bash scripts/ops/sysdba.sh scripts/lab5/06-quitar-propuesta.sql | tee -a "$LOG"
MIG_EVID="$EVID_LAB5/spool" MIG_PARTE=06 bash scripts/deployment/env/08-aplicar-migraciones.sh V005__indices_tiendasur | tee -a "$LOG"
medir "V005"
echo "Evidencia completa en $LOG"
