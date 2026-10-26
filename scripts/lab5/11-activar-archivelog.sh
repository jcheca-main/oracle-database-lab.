#!/usr/bin/env bash
# scripts/lab5/11-activar-archivelog.sh — FRA + modo ARCHIVELOG (idempotente)
# Orden obligatorio: primero el TAMAÑO de la FRA, después su RUTA (al revés: ORA-19802 / ORA-02097).
# El cambio de modo exige la base MONTADA, no abierta: SHUTDOWN IMMEDIATE -> STARTUP MOUNT -> ARCHIVELOG -> OPEN.
set -euo pipefail
source scripts/deployment/env/00-config.sh
FRA="$DATA_ROOT/fra"
FRA_SIZE="${FRA_SIZE:-4G}"
sql() { docker exec -i "$CONT_NAME" sqlplus -s -L / as sysdba; }
MODO=$(printf "SET HEADING OFF FEEDBACK OFF PAGESIZE 0\nSELECT log_mode FROM v\$database;\nEXIT\n" | sql | xargs)
echo "Modo actual: $MODO"
echo "== 1. Carpeta de la FRA dentro del volumen (persistente) =="
docker exec "$CONT_NAME" mkdir -p "$FRA"
echo "== 2. Error de examen: ruta antes que tamaño (ORA-02097/ORA-19802 esperado si la FRA aún no tiene tamaño) =="
printf "ALTER SYSTEM SET db_recovery_file_dest = '%s' SCOPE = BOTH;\nEXIT\n" "$FRA" | sql || true
echo "== 3. Orden correcto: tamaño y luego ruta =="
printf "ALTER SYSTEM SET db_recovery_file_dest_size = %s SCOPE = BOTH;\nALTER SYSTEM SET db_recovery_file_dest = '%s' SCOPE = BOTH;\nEXIT\n" "$FRA_SIZE" "$FRA" | sql
if [ "$MODO" = "ARCHIVELOG" ]; then
  echo "La base ya está en ARCHIVELOG: no hace falta reiniciar."
else
  echo "== 4. Cambio de modo: SHUTDOWN IMMEDIATE -> STARTUP MOUNT -> ALTER DATABASE ARCHIVELOG -> OPEN =="
  sql <<'SQL'
SHUTDOWN IMMEDIATE
STARTUP MOUNT
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
EXIT
SQL
  bash scripts/ops/esperar-healthy.sh
fi
echo "== 5. Comprobación =="
sql <<'SQL'
SET LINESIZE 160 PAGESIZE 100 FEEDBACK OFF
COLUMN name FORMAT A60
ARCHIVE LOG LIST
ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM ARCHIVE LOG CURRENT;
SELECT sequence#, REGEXP_SUBSTR(name, '[^/]+$') AS name, ROUND(blocks * block_size / 1048576, 1) AS mb, archived
  FROM v$archived_log WHERE name IS NOT NULL ORDER BY sequence# DESC FETCH FIRST 4 ROWS ONLY;
SELECT file_type, percent_space_used, number_of_files FROM v$recovery_area_usage WHERE number_of_files > 0;
SELECT name, ROUND(space_limit / 1048576) AS limite_mb, ROUND(space_used / 1048576) AS usado_mb FROM v$recovery_file_dest;
SELECT name AS proceso_archivador FROM v$bgprocess WHERE name LIKE 'ARC%' AND paddr <> '00';
EXIT
SQL
