#!/usr/bin/env bash
# scripts/lab5/14b-perdida-controlfile.sh — simulacro B: se pierde UNA copia del control file
# Con la base parada se borra control03.ctl. El arranque se detiene en NOMOUNT con ORA-00205.
# Solución con multiplexación: copiar una copia sana sobre la perdida y montar. Sin multiplexación,
# habría que restaurar el control file desde un backup (RMAN) y recuperar: mucho más lento y arriesgado.
set -euo pipefail
source scripts/deployment/env/00-config.sh
sql() { docker exec -i "$CONT_NAME" sqlplus -s -L / as sysdba; }
CTL="$DATA_ROOT/FREE/control03.ctl"
docker exec "$CONT_NAME" test -f "$CTL" || { echo "No existe $CTL: ejecuta antes 09-multiplexar-controlfile.sh"; exit 2; }
# La copia sana se lee de control_files (con la base abierta), no se supone su nombre
SANA=$(printf "SET HEADING OFF FEEDBACK OFF PAGESIZE 0\nSELECT name FROM v\$controlfile WHERE name <> '%s' AND ROWNUM = 1;\nEXIT\n" "$CTL" | sql | xargs)
[ -n "$SANA" ] || { echo "No encuentro otra copia del control file: no se ejecuta el simulacro"; exit 2; }
echo "Copia sana que se usará para reparar: $SANA"
echo "== 1. Parada limpia y 'desastre': se borra $CTL =="
printf "SHUTDOWN IMMEDIATE\nEXIT\n" | sql
docker exec "$CONT_NAME" rm -f "$CTL"
echo "== 2. Arranque: falla al MONTAR (ORA-00205 esperado) =="
printf "STARTUP\nSELECT status FROM v\$instance;\nEXIT\n" | sql || true
echo "== 3. Diagnóstico: el alert log dice QUÉ archivo falta =="
docker exec "$CONT_NAME" bash -c 'tail -n 80 /opt/oracle/diag/rdbms/*/*/trace/alert_*.log' \
  | grep -E 'ORA-00210|ORA-00202|ORA-27037|ORA-00205' | tail -4
echo "== 4. Reparación: copiar una copia sana y continuar el arranque desde NOMOUNT =="
docker exec "$CONT_NAME" cp -p "$SANA" "$CTL"
sql <<'SQL'
ALTER DATABASE MOUNT;
ALTER DATABASE OPEN;
SET LINESIZE 120
COLUMN name FORMAT A48
SELECT name, status FROM v$controlfile;
SQL
bash scripts/ops/esperar-healthy.sh
