#!/usr/bin/env bash
# scripts/lab6/05-resumable.sh — asignación reanudable: convertir un fallo de espacio en una pausa (Unidad 5, 5.5.8)
#  1) la aplicación lanza una carga de 20 000 filas (unos 20 MB) en CARGA_HIST.REGISTRO, cuya cuota es de 2 MB
#  2) en lugar de fallar con ORA-01536, la sentencia se SUSPENDE   3) el DBA lo ve y amplía la cuota   4) la carga termina
# Uso: bash scripts/lab6/05-resumable.sh | tee "$EVID_LAB6/script/$(ts)_05-resumable.script.log"
set -euo pipefail
source scripts/deployment/env/00-config.sh
source scripts/ops/cabecera.sh "$(basename "$0" .sh)" || exit 2   # Lab 6: cabecera de evidencia (alumno, hora, contenedor, SCN)
source config/.env
sql() { docker exec -i -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 "$CONT_NAME" sqlplus -s -L / as sysdba; }
APP_LOG=$(mktemp)

echo "== 0. Permisos TEMPORALES para la prueba (deuda de acceso que se paga en la Parte G) y cuota de partida de 2 MB =="
sql <<'SQL'
WHENEVER SQLERROR EXIT FAILURE
SET FEEDBACK ON
ALTER SESSION SET CONTAINER = FREEPDB1;
GRANT INSERT ON carga_hist.registro TO app_academia;
GRANT RESUMABLE TO app_academia;
ALTER USER carga_hist QUOTA 2M ON tbs_academia_hist;
SQL

echo "== 1. La aplicación lanza la carga con RESUMABLE (espera hasta 180 s si le falta espacio) =="
{ printf 'CONNECT app_academia/"%s"@//localhost:1521/academia_app\n' "$APP_ACADEMIA_PWD"; cat <<'SQL'; } \
  | docker exec -i -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 "$CONT_NAME" sqlplus -s /nolog > "$APP_LOG" 2>&1 &
SET FEEDBACK ON
ALTER SESSION ENABLE RESUMABLE TIMEOUT 180 NAME 'carga-historico';
SELECT TO_CHAR(SYSTIMESTAMP, 'HH24:MI:SS') AS inicio FROM dual;
INSERT INTO carga_hist.registro (id, relleno) SELECT level, 'x' FROM dual CONNECT BY level <= 20000;
COMMIT;
SELECT TO_CHAR(SYSTIMESTAMP, 'HH24:MI:SS') AS fin FROM dual;
EXIT
SQL
APP_PID=$!
sleep 12

echo "== 2. El DBA (12 s después): la sentencia no ha fallado, está SUSPENDIDA =="
sql <<'SQL'
SET LINESIZE 160 PAGESIZE 50 FEEDBACK OFF
COLUMN name FORMAT A16
COLUMN status FORMAT A10
COLUMN error_msg FORMAT A70 WORD_WRAPPED
COLUMN event FORMAT A48
COLUMN username FORMAT A13
SELECT name, status, timeout, suspend_time, error_msg FROM cdb_resumable;
SELECT sid, username, event, seconds_in_wait FROM v$session WHERE event LIKE '%suspend%';
SQL
docker exec "$CONT_NAME" bash -c 'grep -a -i "resumable session" /opt/oracle/diag/rdbms/free/FREE/trace/alert_FREE.log | tail -1'

echo "== 3. Menor cambio útil: ampliar la CUOTA del dueño (no el tablespace, que tiene sitio de sobra) =="
printf "ALTER SESSION SET CONTAINER = FREEPDB1;\nALTER USER carga_hist QUOTA 30M ON tbs_academia_hist;\nEXIT\n" | sql
wait "$APP_PID" || true
echo "-- Lo que vio la aplicación: la carga terminó, con una pausa en medio --"
cat "$APP_LOG"; rm -f "$APP_LOG"
docker exec "$CONT_NAME" bash -c 'grep -a -i "resumable session" /opt/oracle/diag/rdbms/free/FREE/trace/alert_FREE.log | tail -2'

echo "== 4. Validación: filas cargadas y cuota consumida =="
sql <<'SQL'
SET LINESIZE 150 FEEDBACK OFF
COLUMN username FORMAT A10
COLUMN tablespace_name FORMAT A18
ALTER SESSION SET CONTAINER = FREEPDB1;
SELECT COUNT(*) AS filas FROM carga_hist.registro;
SELECT username, tablespace_name, ROUND(bytes / 1048576, 1) AS usado_mb, ROUND(max_bytes / 1048576) AS cuota_mb FROM dba_ts_quotas WHERE username = 'CARGA_HIST';
SQL
