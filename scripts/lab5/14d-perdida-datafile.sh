#!/usr/bin/env bash
# scripts/lab5/14d-perdida-datafile.sh — simulacro D: se pierde el datafile de un tablespace de negocio y se recupera con RMAN
#  1) copia RMAN del tablespace  2) un cambio confirmado DESPUÉS de la copia  3) "se rompe el disco": se borra el datafile
#  4) diagnóstico  5) RESTORE + RECOVER del archivo con la base ABIERTA  6) ¿sobrevivió el cambio posterior a la copia? RTO
# Solo funciona en ARCHIVELOG (Parte L): sin el redo archivado, RECOVER no podría rehacer lo ocurrido desde la copia.
set -euo pipefail
source scripts/deployment/env/00-config.sh
sql() { docker exec -i "$CONT_NAME" sqlplus -s -L / as sysdba; }
rman() { docker exec -i "$CONT_NAME" rman target / ; }
DF=$(printf "SET HEADING OFF FEEDBACK OFF PAGESIZE 0\nSELECT d.file# || ' ' || d.name FROM v\$datafile d JOIN v\$tablespace t ON t.ts# = d.ts# AND t.con_id = d.con_id WHERE t.name = 'TBS_ACADEMIA';\nEXIT\n" | sql | xargs)
FNO=${DF%% *}; FNAME=${DF#* }
echo "Archivo víctima: n.º $FNO, $FNAME"
echo "== 1. Copia de seguridad RMAN del tablespace (va a la FRA) =="
rman <<RMAN | grep -E "Starting backup|piece handle|Finished backup"
BACKUP TABLESPACE FREEPDB1:TBS_ACADEMIA TAG 'lab5_simulacro_d';
RMAN
echo "== 2. Un cambio confirmado DESPUÉS de la copia (la copia no lo tiene: solo está en el redo) =="
sql <<'SQL'
SET FEEDBACK OFF
ALTER SESSION SET CONTAINER = FREEPDB1;
UPDATE admin_academia.aca_estudiantes SET estado = 'EGRESADO' WHERE estudiante_id = 104;
COMMIT;
PROMPT 104 -> EGRESADO (confirmado tras la copia)
ALTER SESSION SET CONTAINER = CDB$ROOT;
ALTER SYSTEM SWITCH LOGFILE;
SQL
echo "== 3. Se rompe el disco: el datafile desaparece =="
docker exec "$CONT_NAME" rm -f "$FNAME"
T_FALLO=$(date +%s)
echo "== 4. Diagnóstico: la consulta falla y el alert log dice qué archivo y por qué =="
sql <<'SQL' || true
SET LINESIZE 160 FEEDBACK OFF
ALTER SYSTEM FLUSH BUFFER_CACHE;
ALTER SESSION SET CONTAINER = FREEPDB1;
SELECT COUNT(*) FROM admin_academia.aca_estudiantes;
SQL
docker exec "$CONT_NAME" bash -c 'tail -200 /opt/oracle/diag/rdbms/free/FREE/trace/alert_FREE.log | grep -E "ORA-0111[0-9]|ORA-27041|No such file" | tail -3'
echo "== 5. Reparación: el archivo fuera de línea, RESTORE, RECOVER y otra vez en línea =="
# Desde 21c, si un proceso de fondo detecta el fallo de medio (ORA-63999) Oracle puede CERRAR la PDB entera para protegerla.
# Depende del momento: a veces la PDB sigue abierta y otras ya está MOUNTED. El procedimiento cubre los dos casos.
modo_pdb() { printf "SET HEADING OFF FEEDBACK OFF PAGESIZE 0\nSELECT open_mode FROM v\$pdbs WHERE name = 'FREEPDB1';\nEXIT\n" | sql | xargs; }
T0=$(date +%s)
MODO=$(modo_pdb); CERRADA=0
echo "  Estado de FREEPDB1 antes de reparar: $MODO"
if [ "$MODO" = "READ WRITE" ]; then
  sql <<SQL || { CERRADA=1; echo "  (la PDB se está cerrando: ORA-01089. Se espera a que quede MOUNTED y se repara igual)"; }
WHENEVER SQLERROR EXIT FAILURE
SET FEEDBACK ON
ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER DATABASE DATAFILE $FNO OFFLINE;
SQL
else
  CERRADA=1
  echo "  Oracle cerró la PDB al detectar el fallo de medio (alert log: ORA-63999): se repara con la PDB montada y después se abre"
fi
# Un cierre de PDB a medias y un RESTORE a la vez se pisan: antes de seguir, la PDB debe estar abierta o completamente montada
if [ "$CERRADA" = 1 ]; then
  for _ in $(seq 1 60); do [ "$(modo_pdb)" = "MOUNTED" ] && break; sleep 1; done
  sleep 3
fi
echo "  Estado de FREEPDB1 al empezar la reparación: $(modo_pdb)"
SALIDA=$(rman <<RMAN
RESTORE DATAFILE $FNO;
RECOVER DATAFILE $FNO;
RMAN
) || { echo "$SALIDA" | grep -E "RMAN-0[0-9]{4}|ORA-"; exit 1; }
echo "$SALIDA" | grep -E "Starting (restore|recover)|restoring datafile|archived log|media recovery complete|Finished (restore|recover)"
sql <<SQL
SET FEEDBACK ON
ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER DATABASE DATAFILE $FNO ONLINE;
SQL
MODO=$(modo_pdb)
if [ "$MODO" != "READ WRITE" ]; then
  echo "  FREEPDB1 está $MODO: se abre de nuevo"
  printf "ALTER PLUGGABLE DATABASE FREEPDB1 OPEN;\nEXIT\n" | sql
fi
echo "  Estado de FREEPDB1 tras reparar: $(modo_pdb)"
T1=$(date +%s)
echo "== 6. ¿Sobrevivió el cambio posterior a la copia? =="
sql <<'SQL'
SET FEEDBACK OFF
ALTER SESSION SET CONTAINER = FREEPDB1;
SELECT estudiante_id, estado FROM admin_academia.aca_estudiantes WHERE estudiante_id = 104;
PROMPT (EGRESADO = RECOVER aplicó el redo archivado posterior a la copia: RPO = 0, no se perdió nada)
PROMPT Devolvemos la fila 104 a ACTIVO para que el laboratorio se pueda repetir
UPDATE admin_academia.aca_estudiantes SET estado = 'ACTIVO' WHERE estudiante_id = 104;
COMMIT;
SELECT COUNT(*) AS estudiantes FROM admin_academia.aca_estudiantes;
SQL
echo "== 7. Métricas del simulacro =="
echo "  RPO (datos perdidos): 0 (copia + redo archivado + redo en línea)"
echo "  RTO (archivo fuera de línea -> en línea): $((T1 - T0)) s; desde el fallo: $((T1 - T_FALLO)) s"
echo "  Si la PDB siguió abierta, solo TBS_ACADEMIA estuvo inaccesible; si Oracle la cerró (ORA-63999), toda FREEPDB1 lo estuvo: el RTO lo refleja"
