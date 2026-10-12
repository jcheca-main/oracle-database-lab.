#!/usr/bin/env bash
# scripts/deployment/env/12-instalar-ords.sh
set -euo pipefail
source scripts/deployment/env/00-config.sh
set -a; source config/.env; set +a
ORDS="$ORDS_HOME/bin/ords"
BASE="https://download.oracle.com/otn_software/java/ords"
echo "== 1. Java (ORDS requiere 17 o 21) =="
java -version 2>&1 | head -n 1
echo "== 2. Programa ORDS en $ORDS_HOME =="
if [ ! -x "$ORDS" ]; then
 wget -q -O /tmp/ords-latest.zip "$BASE/ords-latest.zip"
 unzip -q -o /tmp/ords-latest.zip -d "$ORDS_HOME"
fi
"$ORDS" --version
echo "== 3. Instalacion en FREEPDB1 (no interactiva) =="
if [ -f "$ORDS_CONFIG/databases/default/pool.xml" ]; then
 echo "ORDS ya esta configurado; no se reinstala."
else
 printf '%s\n%s\n' "$ORACLE_PWD" "$ORDS_PUBLIC_PWD" |
 "$ORDS" --config "$ORDS_CONFIG" install \
 --admin-user "SYS AS SYSDBA" \
 --db-hostname localhost \
 --db-port "$PORT_DB" \
 --db-servicename "$SERVICE_PDB" \
 --feature-db-api true \
 --feature-rest-enabled-sql true \
 --feature-sdw true \
 --log-folder "$ORDS_LOGS" \
 --password-stdin
fi
echo "== 4. Puerto HTTP del modo standalone =="
"$ORDS" --config "$ORDS_CONFIG" \
 config set standalone.http.port "$ORDS_PORT"
