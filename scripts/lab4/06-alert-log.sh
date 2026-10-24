#!/usr/bin/env bash
# scripts/lab4/06-alert-log.sh — lo que la instancia contó en el alert log durante la parada y el arranque
# El alert log es el primer sitio que mira un DBA (y un SRE) ante cualquier incidente.
set -euo pipefail
source scripts/deployment/env/00-config.sh
ALERT=$(docker exec "$CONT_NAME" bash -c 'ls /opt/oracle/diag/rdbms/*/*/trace/alert_*.log | head -1')
echo "== Alert log: $ALERT =="
docker exec "$CONT_NAME" tail -n "${1:-400}" "$ALERT" \
  | grep -E '^20[0-9]{2}-|Shutting down|Starting ORACLE|Instance shutdown complete|ALTER DATABASE|Completed:|Pluggable database .* opened|Opening pdb|Database Characterset|Successful (mount|open)|SCN|Crash Recovery|Thread 1 (opened|advanced)|ORA-' \
  | grep -vE '^20[0-9]{2}-[0-9-]+T[0-9:.]+[+-][0-9:]+$' | tail -n 45
