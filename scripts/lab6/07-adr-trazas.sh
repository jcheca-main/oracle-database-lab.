#!/usr/bin/env bash
# scripts/lab6/07-adr-trazas.sh — el diario de Oracle (ADR) y la traza de una sesión concreta (Unidad 5, 5.7.4 a 5.7.6)
# Uso: bash scripts/lab6/07-adr-trazas.sh | tee "$EVID_LAB6/script/$(ts)_07-adr-trazas.script.log"
set -euo pipefail
source scripts/deployment/env/00-config.sh
source scripts/ops/cabecera.sh "$(basename "$0" .sh)" || exit 2   # Lab 6: cabecera de evidencia (alumno, hora, contenedor, SCN)
source config/.env
sql() { docker exec -i -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 "$CONT_NAME" sqlplus -s -L / as sysdba; }
echo "== 1. Dónde está el ADR (V\$DIAG_INFO) =="
sql <<'SQL'
SET LINESIZE 150 PAGESIZE 50 FEEDBACK OFF
COLUMN name FORMAT A22
COLUMN value FORMAT A70
SELECT name, value FROM v$diag_info ORDER BY inst_id, name;
SQL
echo "== 2. El alert log existe dos veces: en texto (trace/) y en XML (alert/), que es el que lee V\$DIAG_ALERT_EXT =="
docker exec "$CONT_NAME" bash -c 'cd /opt/oracle/diag/rdbms/free/FREE && ls -l trace/alert_FREE.log alert/log.xml && echo "Trazas en trace/: $(ls trace/*.trc | wc -l)"'
echo "== 3. Problemas e incidentes (un problema agrupa los incidentes del mismo error crítico) =="
sql <<'SQL'
SET LINESIZE 150 PAGESIZE 50 FEEDBACK OFF
COLUMN problem_key FORMAT A30
COLUMN error_arg1 FORMAT A24
SELECT problem_id, problem_key, TO_CHAR(firstinc_time, 'YYYY-MM-DD HH24:MI') AS primero, TO_CHAR(lastinc_time, 'YYYY-MM-DD HH24:MI') AS ultimo FROM v$diag_problem;
SELECT problem_id, COUNT(*) AS incidentes, MAX(error_number) AS error_number, MAX(error_arg1) AS error_arg1 FROM v$diag_incident GROUP BY problem_id;
SQL
echo "== 4. ADRCI, si tu imagen lo incluye (la oficial de Oracle lo trae; algunas imágenes de la comunidad, no) =="
if docker exec "$CONT_NAME" bash -c 'command -v adrci' > /dev/null 2>&1; then
  docker exec "$CONT_NAME" adrci exec="show homes; set home diag/rdbms/free/FREE; show problem; show control" | grep -vE '^\s*$' || true
else
  echo "  adrci no está en esta imagen: la misma información la dan las vistas V\$DIAG_* de los pasos 1 y 3"
fi
echo "== 5. Trazar la sesión de OTRO usuario sin pedirle nada ni reiniciar (DBMS_MONITOR) =="
APP_LOG=$(mktemp)
{ printf 'CONNECT app_academia/"%s"@//localhost:1521/academia_app\n' "$APP_ACADEMIA_PWD"; cat <<'SQL'; } \
  | docker exec -i -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 "$CONT_NAME" sqlplus -s /nolog > "$APP_LOG" 2>&1 &
ALTER SESSION SET tracefile_identifier = 'lab6_app';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('ficha-alumno', 'consulta-activos')
EXEC DBMS_SESSION.SLEEP(8)
SELECT COUNT(*) AS activos FROM admin_academia.aca_estudiantes WHERE estado = 'ACTIVO';
EXEC DBMS_SESSION.SLEEP(3)
EXIT
SQL
APP_PID=$!
sleep 4
SID_SER=$(printf "SET HEADING OFF FEEDBACK OFF PAGESIZE 0\nSELECT sid || ',' || serial# FROM v\$session WHERE username = 'APP_ACADEMIA' AND module = 'ficha-alumno' AND ROWNUM = 1;\nEXIT\n" | sql | xargs)
[ -n "$SID_SER" ] || { echo "No encuentro la sesión de la aplicación"; cat "$APP_LOG"; exit 1; }
TRC=$(printf "SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 300\nSELECT p.tracefile FROM v\$session s JOIN v\$process p ON p.addr = s.paddr WHERE s.sid = ${SID_SER%%,*};\nEXIT\n" | sql | xargs)
echo "  Sesión $SID_SER · su traza irá a $TRC"
printf "EXEC DBMS_MONITOR.SESSION_TRACE_ENABLE(session_id => %s, serial_num => %s, waits => TRUE, binds => FALSE)\nEXIT\n" "${SID_SER%%,*}" "${SID_SER##*,}" | sql
wait "$APP_PID" || true
cat "$APP_LOG"; rm -f "$APP_LOG"
echo "-- Extracto de la traza en bruto (una línea de cada tipo) --"
docker exec "$CONT_NAME" bash -c "grep -a -m1 '^PARSING IN CURSOR' '$TRC'; grep -a -m1 '^EXEC #' '$TRC'; grep -a -m1 '^FETCH #.*dep=0' '$TRC'; grep -a -m1 \"^WAIT #.*nam='PL/SQL lock timer'\" '$TRC'" | cut -c1-140 || true
echo "-- tkprof la convierte en un informe legible (solo la consulta de la aplicación) --"
if docker exec "$CONT_NAME" bash -c 'command -v tkprof' > /dev/null 2>&1; then
  docker exec "$CONT_NAME" bash -c "tkprof '$TRC' /tmp/lab6_app.txt sys=no > /dev/null && grep -a -A12 'SELECT COUNT(\*) AS activos' /tmp/lab6_app.txt | sed -n '1,13p'"
else
  echo "  tkprof no está en esta imagen: lee directamente las líneas FETCH (cr = lecturas lógicas, r = filas)"
fi
