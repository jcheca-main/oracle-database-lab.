#!/usr/bin/env bash
# scripts/lab4/11-archivos-so.sh — los mismos archivos vistos desde Linux: tamaño real, enlaces y carpetas del ADR
# Uso: bash scripts/lab4/11-archivos-so.sh | tee "$EVID_LAB4/script/$(ts)_11-archivos-so.script.log"
set -euo pipefail
source scripts/deployment/env/00-config.sh
docker exec "$CONT_NAME" bash -c '
echo "== 1. El volumen (/opt/oracle/oradata): lo que la copia de seguridad debe contener =="
find /opt/oracle/oradata -maxdepth 3 -type f \( -name "*.dbf" -o -name "*.ctl" -o -name "*.log" -o -name "*.ora" -o -name "orapw*" \) \
  -printf "%10s bytes  %p\n" | sort -k3
echo "== 2. \$ORACLE_HOME/dbs: SPFILE y password file (¿archivos o enlaces al volumen?) =="
ls -l "$ORACLE_HOME/dbs" | grep -E "spfile|orapw|init" || true
echo "== 3. El ADR (diagnostic_dest): alert log y trazas =="
ADR=/opt/oracle/diag/rdbms/free/FREE
ls -l "$ADR/trace/alert_FREE.log"
echo "trazas (.trc) en $ADR/trace: $(ls "$ADR/trace" | grep -c "\.trc$")  ·  tamaño total del ADR: $(du -sh /opt/oracle/diag | cut -f1)"
echo "== 4. ¿Está el ADR dentro del volumen? (si no, el alert log se pierde al recrear el contenedor) =="
case "$(readlink -f /opt/oracle/diag)" in
  /opt/oracle/oradata/*) echo "  SÍ: /opt/oracle/diag está en el volumen" ;;
  *) echo "  NO: /opt/oracle/diag vive en la capa del contenedor. Al recrearlo, el alert log empieza de cero." ;;
esac
' 2>&1
