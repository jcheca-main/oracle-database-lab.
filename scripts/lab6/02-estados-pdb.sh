#!/usr/bin/env bash
# scripts/lab6/02-estados-pdb.sh — los estados de una PDB y por qué «arriba» exige evidencia (Unidad 5, 5.2.5 a 5.2.8)
#  1) estado actual y estado guardado      2) READ ONLY: ORA-16000 al escribir y ORA-65019 al reabrir sin FORCE
#  3) RESTRICTED: C##OPS_RO no entra (ORA-01035)
#  4) sin estado guardado, un reinicio deja FREEPDB1 en MOUNTED y nadie entra por su servicio (ORA-01109 u ORA-12514)
#  5) SAVE STATE + segundo reinicio: la PDB vuelve sola. Se valida con scripts/ops/validar-arranque.sql
# Reinicia la instancia DOS veces (unos 2-3 minutos). Nadie más debe estar usando la base.
# Uso: bash scripts/lab6/02-estados-pdb.sh | tee "$EVID_LAB6/script/$(ts)_02-estados-pdb.script.log"
set -euo pipefail
source scripts/deployment/env/00-config.sh
source scripts/ops/cabecera.sh "$(basename "$0" .sh)" || exit 2   # Lab 6: cabecera de evidencia (alumno, hora, contenedor, SCN)
dba() { docker exec -i -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 "$CONT_NAME" sqlplus -s -L / as sysdba; }
estado() {
dba <<'SQL'
SET LINESIZE 150 PAGESIZE 50 FEEDBACK OFF
COLUMN name FORMAT A10
COLUMN estado_guardado FORMAT A22
SELECT p.name, p.open_mode, p.restricted, NVL(s.state, '(sin estado guardado)') AS estado_guardado
  FROM v$pdbs p LEFT JOIN cdb_pdb_saved_states s ON s.con_name = p.name WHERE p.name = 'FREEPDB1';
SQL
}
# Intento de conexión de C##OPS_RO por el servicio freepdb1: muestra solo la línea del error (o «conectado»)
probar_ro() {
  local tmp; tmp=$(mktemp)
  printf 'SET HEADING OFF FEEDBACK OFF\nSELECT %s FROM dual;\n' "'conectado a ' || SYS_CONTEXT('USERENV','CON_NAME')" > "$tmp.sql"
  bash scripts/ops/ro.sh "$tmp.sql" freepdb1 2>&1 | grep -E 'ORA-|conectado' | awk 'NR<=2' || true
  rm -f "$tmp" "$tmp.sql"
}

echo "== 1. Punto de partida =="
estado

echo "== 2. READ ONLY: se puede consultar, no escribir =="
dba <<'SQL'
SET FEEDBACK ON
ALTER PLUGGABLE DATABASE freepdb1 CLOSE IMMEDIATE;
ALTER PLUGGABLE DATABASE freepdb1 OPEN READ ONLY;
ALTER SESSION SET CONTAINER = freepdb1;
SELECT COUNT(*) AS estudiantes FROM admin_academia.aca_estudiantes;
PROMPT -- Intento de escritura (error esperado: ORA-16000)
UPDATE admin_academia.aca_estudiantes SET estado = estado WHERE estudiante_id = 101;
ALTER SESSION SET CONTAINER = CDB$ROOT;
PROMPT -- Intento de reabrir en lectura y escritura sin cerrar (error esperado: ORA-65019)
ALTER PLUGGABLE DATABASE freepdb1 OPEN READ WRITE;
PROMPT -- FORCE la cierra y la abre en el modo pedido en un solo paso
ALTER PLUGGABLE DATABASE freepdb1 OPEN READ WRITE FORCE;
SQL
estado

echo "== 3. RESTRICTED: solo entra quien tiene RESTRICTED SESSION =="
dba <<'SQL'
SET FEEDBACK ON
ALTER PLUGGABLE DATABASE freepdb1 CLOSE IMMEDIATE;
ALTER PLUGGABLE DATABASE freepdb1 OPEN RESTRICTED;
SQL
estado
echo "-- C##OPS_RO intenta entrar (error esperado: ORA-01035):"
probar_ro
dba <<'SQL'
SET FEEDBACK ON
ALTER PLUGGABLE DATABASE freepdb1 CLOSE IMMEDIATE;
ALTER PLUGGABLE DATABASE freepdb1 OPEN;
SQL
echo "-- Reabierta sin restricción:"
probar_ro

echo "== 4. Reinicio SIN estado guardado =="
dba <<'SQL'
SET FEEDBACK ON
ALTER PLUGGABLE DATABASE freepdb1 DISCARD STATE;
SHUTDOWN IMMEDIATE
STARTUP
SQL
estado
echo "-- La aplicación (y C##OPS_RO) intentan entrar por el servicio freepdb1 (error esperado: ORA-01109 u ORA-12514):"
probar_ro

echo "== 5. Abrir, GUARDAR EL ESTADO y comprobarlo con otro reinicio =="
dba <<'SQL'
SET FEEDBACK ON
ALTER PLUGGABLE DATABASE freepdb1 OPEN;
ALTER PLUGGABLE DATABASE freepdb1 SAVE STATE;
SHUTDOWN IMMEDIATE
STARTUP
SQL
estado
echo "-- Validación posterior al arranque (C##OPS_RO, solo lectura):"
bash scripts/ops/ro.sh scripts/ops/validar-arranque.sql
