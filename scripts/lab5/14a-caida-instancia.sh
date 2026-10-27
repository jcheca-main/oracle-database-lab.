#!/usr/bin/env bash
# scripts/lab5/14a-caida-instancia.sh — simulacro A: caída brusca de la instancia (SHUTDOWN ABORT)
# Equivale a un corte de luz: sin checkpoint final. Al arrancar, SMON hace la recuperación de instancia
# (roll forward con el redo y roll back con el undo) sin que nadie intervenga.
set -euo pipefail
source scripts/deployment/env/00-config.sh
sql() { docker exec -i "$CONT_NAME" sqlplus -s -L / as sysdba; }
echo "== 1. Una transacción confirmada y otra SIN confirmar justo antes de la caída =="
sql <<'SQL'
SET FEEDBACK OFF
ALTER SESSION SET CONTAINER = FREEPDB1;
UPDATE admin_academia.aca_estudiantes SET estado = 'EGRESADO' WHERE estudiante_id = 102;
COMMIT;
UPDATE admin_academia.aca_estudiantes SET estado = 'INACTIVO' WHERE estudiante_id = 103;
PROMPT 102 -> EGRESADO (confirmado) · 103 -> INACTIVO (sin confirmar) · y ahora... SHUTDOWN ABORT
ALTER SESSION SET CONTAINER = CDB$ROOT;
SHUTDOWN ABORT
SQL
INICIO=$(date -u +%Y-%m-%dT%H:%M:%S)
echo "== 2. Arranque normal: la recuperación de instancia es automática =="
printf "STARTUP\nEXIT\n" | sql
bash scripts/ops/esperar-healthy.sh
echo "== 3. ¿Qué sobrevivió? (lo confirmado sí; lo no confirmado se deshizo) =="
sql <<'SQL'
SET FEEDBACK OFF
ALTER SESSION SET CONTAINER = FREEPDB1;
SELECT estudiante_id, estado FROM admin_academia.aca_estudiantes WHERE estudiante_id IN (102, 103) ORDER BY 1;
PROMPT Devolvemos la fila 102 a ACTIVO para que el laboratorio se pueda repetir
UPDATE admin_academia.aca_estudiantes SET estado = 'ACTIVO' WHERE estudiante_id = 102;
COMMIT;
SQL
echo "== 4. El alert log cuenta la recuperación de instancia =="
docker exec "$CONT_NAME" bash -c 'tail -n 400 /opt/oracle/diag/rdbms/*/*/trace/alert_*.log' \
  | grep -E 'Shutting down .*\(abort\)|shutdown \(abort\)|Beginning crash recovery|Recovery starting at|redo scan|need recovery|redo application|Completed crash recovery|opened at log sequence' \
  | tail -12
