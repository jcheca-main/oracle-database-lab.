#!/usr/bin/env bash
# scripts/lab4/05-instancia-so.sh — la misma instancia vista desde Linux (procesos, memoria, archivos, listener)
set -euo pipefail
source scripts/deployment/env/00-config.sh
echo "== 1. Procesos de la instancia FREE (docker top = ps dentro del contenedor) =="
docker top "$CONT_NAME" -eo pid,user,rss,args | grep -E '(ora|db)_[a-z0-9]+_FREE' | awk 'NR <= 15'
echo "   ... total de procesos de background (db_*_FREE en 26ai; ora_*_FREE en versiones anteriores): $(docker top "$CONT_NAME" -eo pid,args | grep -cE ' (ora|db)_[a-z0-9]+_FREE')"
echo "== 2. Procesos servidor (uno por sesión dedicada) y listener =="
docker top "$CONT_NAME" -eo pid,user,args | grep -E 'oracleFREE|tnslsnr' || true
echo "   (si no ves ningún oracleFREE es que no hay sesiones abiertas por red: abre SQLcl en otra terminal y repite)"
echo "== 3. Memoria del contenedor (incluye la SGA) =="
docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}' "$CONT_NAME"
echo "== 4. La base de datos en disco: archivos del CDB y de FREEPDB1 =="
docker exec "$CONT_NAME" bash -c 'ls -lh /opt/oracle/oradata/FREE | grep -v ^total; echo "-- FREEPDB1 --"; ls -lh /opt/oracle/oradata/FREE/FREEPDB1 | grep -v ^total'
echo "== 5. Listener: servicios registrados =="
docker exec "$CONT_NAME" lsnrctl status | grep -E 'Service|Instance|Listening|Uptime'
