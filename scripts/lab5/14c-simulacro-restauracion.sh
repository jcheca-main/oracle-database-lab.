#!/usr/bin/env bash
# scripts/lab5/14c-simulacro-restauracion.sh — simulacro C: borrado de una tabla y medida del RTO
#  1) copia "lab5-pre-simulacro"  2) DROP sin PURGE -> la papelera (recycle bin) lo arregla en segundos
#  3) DROP ... PURGE -> ya no hay papelera: se restaura la copia y se mide cuánto tarda (RTO)
set -euo pipefail
source scripts/deployment/env/00-config.sh
sql() { docker exec -i "$CONT_NAME" sqlplus -s -L / as sysdba; }
contar() { printf "SET HEADING OFF FEEDBACK OFF PAGESIZE 0\nALTER SESSION SET CONTAINER = FREEPDB1;\nSELECT COUNT(*) FROM admin_academia.aca_matriculas;\nEXIT\n" | sql | grep -E '^[[:space:]]*[0-9]+|ORA-' | xargs; }
echo "== 1. Copia previa al simulacro =="
bash scripts/ops/backup-estado.sh lab5-pre-simulacro | tail -3
COPIA=$(ls -d backups/*_lab5-pre-simulacro | tail -1)
T_COPIA=$(date +%s)
echo "Matrículas antes: $(contar)"
echo "== 2. Error humano leve: DROP TABLE sin PURGE -> FLASHBACK TABLE ... TO BEFORE DROP =="
sql <<'SQL'
SET FEEDBACK ON LINESIZE 140
COLUMN original_name FORMAT A16
COLUMN object_name FORMAT A32
COLUMN type FORMAT A6
ALTER SESSION SET CONTAINER = FREEPDB1;
DROP TABLE admin_academia.aca_matriculas;
SELECT original_name, object_name, type, droptime FROM dba_recyclebin WHERE owner = 'ADMIN_ACADEMIA' ORDER BY type DESC;
FLASHBACK TABLE admin_academia.aca_matriculas TO BEFORE DROP;
SQL
echo "Matrículas tras FLASHBACK TABLE: $(contar)"
echo "== 3. Error humano grave: DROP TABLE ... PURGE (sin papelera) =="
printf "ALTER SESSION SET CONTAINER = FREEPDB1;\nDROP TABLE admin_academia.aca_matriculas PURGE;\nEXIT\n" | sql
echo "Matrículas ahora: $(contar)"
T_FALLO=$(date +%s)
echo "== 4. Restauración de la copia, cronometrada =="
T0=$(date +%s)
bash scripts/ops/restaurar-estado.sh "$COPIA" --si | tail -12
T1=$(date +%s)
echo "Matrículas tras restaurar: $(contar)"
echo "== 5. Métricas del simulacro =="
echo "  RPO (datos perdidos): todo lo hecho en los $((T_FALLO - T_COPIA)) s entre la copia y el fallo"
echo "  RTO (tiempo de restauración): $((T1 - T0)) s"
