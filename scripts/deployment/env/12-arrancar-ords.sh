#!/usr/bin/env bash
# scripts/deployment/env/12-arrancar-ords.sh
set -euo pipefail
source scripts/deployment/env/00-config.sh
ORDS="$ORDS_HOME/bin/ords"
LOG="$ORDS_LOGS/ords-serve.log"
URL="http://localhost:$ORDS_PORT/ords/sql-developer"
if tmux has-session -t ords 2>/dev/null; then
 echo "ORDS ya esta en marcha (sesion tmux 'ords')."
else
 tmux new-session -d -s ords \
 "$ORDS --config $ORDS_CONFIG serve 2>&1 | tee -a $LOG"
 echo "ORDS arrancando en segundo plano..."
fi
code="000"
for i in $(seq 1 30); do
 code=$(curl -s -o /dev/null -w '%{http_code}' "$URL" || true)
 if [ "$code" = "200" ] || [ "$code" = "302" ]; then break; fi
 sleep 2
done
echo "Database Actions responde con HTTP $code"
if ! ss -tlnp | grep ":$ORDS_PORT"; then
 echo "AVISO: nada escucha en $ORDS_PORT; revisa $LOG"
fi
