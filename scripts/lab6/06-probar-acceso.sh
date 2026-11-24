#!/usr/bin/env bash
# scripts/lab6/06-probar-acceso.sh — validar el gobierno del acceso con las identidades reales (Unidad 5, 5.6.4 a 5.6.6)
#  1) ANA_GARCIA entra por freepdb1 y prueba lo que puede y lo que no   2) APP_ACADEMIA sigue funcionando con su rol
#  3) tres contraseñas erróneas bloquean a ANA (LOCKED(TIMED)) incluso con la correcta   4) el DBA la desbloquea
# Uso: bash scripts/lab6/06-probar-acceso.sh | tee "$EVID_LAB6/script/$(ts)_06-probar-acceso.script.log"
set -uo pipefail
source scripts/deployment/env/00-config.sh
source scripts/ops/cabecera.sh "$(basename "$0" .sh)" || exit 2   # Lab 6: cabecera de evidencia (alumno, hora, contenedor, SCN)
source config/.env
dba() { docker exec -i -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 "$CONT_NAME" sqlplus -s -L / as sysdba; }
echo "== 1. ANA_GARCIA (persona de secretaría) entra por el servicio freepdb1 =="
printf 'CONNECT ana_garcia/"%s"@//localhost:%s/freepdb1\n@scripts/lab6/06-sesion-ana.sql\nEXIT\n' \
  "$ANA_GARCIA_PWD" "$PORT_DB" | sql -S /nolog 2>&1 || true
echo "== 2. APP_ACADEMIA sigue funcionando tras pagar la deuda de acceso =="
bash scripts/ops/app.sh scripts/lab6/06-app-sigue.sql
echo "== 3. Tres contraseñas erróneas y después la correcta =="
docker exec -i -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 "$CONT_NAME" sqlplus -s /nolog <<SQL 2>&1 | grep -E "ORA-|Connected" || true
CONNECT ana_garcia/"Mala_1x"@//localhost:1521/freepdb1
CONNECT ana_garcia/"Mala_2x"@//localhost:1521/freepdb1
CONNECT ana_garcia/"Mala_3x"@//localhost:1521/freepdb1
CONNECT ana_garcia/"$ANA_GARCIA_PWD"@//localhost:1521/freepdb1
EXIT
SQL
dba <<'SQL'
SET LINESIZE 120 FEEDBACK OFF
COLUMN username FORMAT A12
COLUMN account_status FORMAT A16
ALTER SESSION SET CONTAINER = FREEPDB1;
SELECT username, account_status, lock_date FROM dba_users WHERE username = 'ANA_GARCIA';
PROMPT -- El DBA atiende la incidencia (en el mundo real: tras confirmar la identidad de Ana por otro canal)
ALTER USER ana_garcia ACCOUNT UNLOCK;
SELECT username, account_status FROM dba_users WHERE username = 'ANA_GARCIA';
SQL
