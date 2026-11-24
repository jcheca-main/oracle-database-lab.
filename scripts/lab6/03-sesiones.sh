#!/usr/bin/env bash
# scripts/lab6/03-sesiones.sh — el camino de una conexión y cómo se interviene una sesión (Unidad 5, 5.3.1, 5.3.5 y 5.3.8)
#  1) el listener anuncia los servicios   2) la aplicación entra por academia_app, se identifica y deja un UPDATE abierto
#  3) el DBA la observa (V$SESSION + V$PROCESS + V$TRANSACTION)   4) CANCEL SQL: cae la llamada, NO la transacción
#  5) KILL SESSION IMMEDIATE: la sesión muere y su UPDATE se deshace   6) SYSOPER frente a SYSDBA
# Uso: bash scripts/lab6/03-sesiones.sh | tee "$EVID_LAB6/script/$(ts)_03-sesiones.script.log"
set -euo pipefail
source scripts/deployment/env/00-config.sh
source scripts/ops/cabecera.sh "$(basename "$0" .sh)" || exit 2   # Lab 6: cabecera de evidencia (alumno, hora, contenedor, SCN)
source config/.env
[ -n "${APP_ACADEMIA_PWD:-}" ] || { echo "Falta APP_ACADEMIA_PWD en config/.env (Parte A.3)" >&2; exit 2; }
sql() { docker exec -i -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 "$CONT_NAME" sqlplus -s -L / as sysdba; }
APP_LOG=$(mktemp)

echo "== 1. ¿Qué servicios anuncia el listener? (deben aparecer freepdb1 y academia_app, READY) =="
docker exec "$CONT_NAME" lsnrctl status | awk '/^Service "(academia_app|freepdb1)"/ {print; getline; print}' 

echo "== 2. La aplicación entra por el servicio academia_app y deja la fila 101 modificada SIN confirmar =="
# La sesión de la aplicación corre en segundo plano: entra por la red (listener), como una aplicación real
{ printf 'CONNECT app_academia/"%s"@//localhost:1521/academia_app\n' "$APP_ACADEMIA_PWD"; cat <<'SQL'; } \
  | docker exec -i -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 "$CONT_NAME" sqlplus -s /nolog > "$APP_LOG" 2>&1 &
SET FEEDBACK ON LINESIZE 150
COLUMN contenedor FORMAT A10
COLUMN servicio FORMAT A13
COLUMN usuario FORMAT A13
COLUMN autenticacion FORMAT A13
COLUMN sid FORMAT A5
SELECT SYS_CONTEXT('USERENV','CON_NAME') AS contenedor, SYS_CONTEXT('USERENV','SERVICE_NAME') AS servicio,
       SYS_CONTEXT('USERENV','SESSION_USER') AS usuario, SYS_CONTEXT('USERENV','AUTHENTICATION_METHOD') AS autenticacion,
       SYS_CONTEXT('USERENV','SID') AS sid FROM dual;
EXEC DBMS_APPLICATION_INFO.SET_MODULE(module_name => 'matriculas', action_name => 'cierre-periodo')
EXEC DBMS_SESSION.SET_IDENTIFIER('ana.garcia@ucam')
UPDATE admin_academia.aca_estudiantes SET estado = 'EGRESADO' WHERE estudiante_id = 101;
EXEC DBMS_SESSION.SLEEP(40)
SELECT 'sigo viva' AS mensaje FROM dual;
EXEC DBMS_SESSION.SLEEP(40)
ROLLBACK;
EXIT
SQL
APP_PID=$!
sleep 8

echo "== 3. Lo que ve el DBA desde la raíz: quién es, por dónde entró, qué hace y cuánto tendría que deshacer =="
sql <<'SQL'
SET LINESIZE 200 PAGESIZE 50 FEEDBACK OFF
COLUMN username FORMAT A12
COLUMN service_name FORMAT A12
COLUMN module FORMAT A10
COLUMN action FORMAT A14
COLUMN client_identifier FORMAT A15 HEADING CLIENTE
COLUMN event FORMAT A17
COLUMN sid FORMAT 9999
COLUMN serial# FORMAT 99999
COLUMN con_id FORMAT 99 HEADING CON
COLUMN spid FORMAT A7
COLUMN status FORMAT A8
SELECT s.sid, s.serial#, s.username, s.service_name, s.module, s.action, s.client_identifier,
       s.event, s.con_id, p.spid
  FROM v$session s JOIN v$process p ON p.addr = s.paddr
 WHERE s.username = 'APP_ACADEMIA';
SELECT s.sid, t.used_ublk, t.used_urec, t.start_time
  FROM v$transaction t JOIN v$session s ON s.taddr = t.addr WHERE s.username = 'APP_ACADEMIA';
SQL
SID_SER=$(printf "SET HEADING OFF FEEDBACK OFF PAGESIZE 0\nSELECT sid || ',' || serial# FROM v\$session WHERE username = 'APP_ACADEMIA' AND ROWNUM = 1;\nEXIT\n" | sql | xargs)
[ -n "$SID_SER" ] || { echo "No encuentro la sesión de APP_ACADEMIA. Mira su salida:"; cat "$APP_LOG"; exit 1; }
SPID=$(printf "SET HEADING OFF FEEDBACK OFF PAGESIZE 0\nSELECT p.spid FROM v\$session s JOIN v\$process p ON p.addr = s.paddr WHERE s.username = 'APP_ACADEMIA' AND ROWNUM = 1;\nEXIT\n" | sql | xargs)
echo "   El SPID $SPID es un proceso de Linux dentro del contenedor:"
# La imagen no trae «ps»: /proc es la fuente de la que bebe ps (Lab 4, Parte H)
docker exec "$CONT_NAME" bash -c "printf 'PID %s  ' $SPID; tr '\\0' ' ' < /proc/$SPID/cmdline; echo; grep -E '^(State|VmRSS)' /proc/$SPID/status" || true

echo "== 4. CANCEL SQL '$SID_SER': cancela la llamada en curso (el SLEEP), pero la transacción SIGUE abierta =="
printf "ALTER SYSTEM CANCEL SQL '%s';\nEXIT\n" "$SID_SER" | sql
sleep 3
sql <<'SQL'
SET FEEDBACK OFF
SELECT COUNT(*) AS transacciones_abiertas_de_la_app
  FROM v$transaction t JOIN v$session s ON s.taddr = t.addr WHERE s.username = 'APP_ACADEMIA';
SQL

echo "== 5. KILL SESSION '$SID_SER' IMMEDIATE: la sesión termina y su UPDATE se DESHACE =="
printf "ALTER SYSTEM KILL SESSION '%s' IMMEDIATE;\nEXIT\n" "$SID_SER" | sql || true
sleep 3
sql <<'SQL'
SET FEEDBACK OFF
SELECT COUNT(*) AS sesiones_app_vivas FROM v$session WHERE username = 'APP_ACADEMIA';
ALTER SESSION SET CONTAINER = FREEPDB1;
SELECT estudiante_id, estado FROM admin_academia.aca_estudiantes WHERE estudiante_id = 101;
SQL
wait "$APP_PID" 2>/dev/null || true
echo "-- Lo que vio la aplicación, de principio a fin --"
cat "$APP_LOG"
rm -f "$APP_LOG"
echo "-- Lo que quedó en el alert log: quién mató a quién --"
docker exec "$CONT_NAME" bash -c 'grep -a -A6 "KILL SESSION for sid" /opt/oracle/diag/rdbms/free/FREE/trace/alert_FREE.log | tail -7'

echo "== 6. Escalera de privilegios: SYSOPER opera, pero no ve los datos =="
docker exec -i -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 "$CONT_NAME" sqlplus -s -L / as sysoper <<'SQL' || true
SHOW USER
SELECT COUNT(*) FROM dba_users;
SQL
