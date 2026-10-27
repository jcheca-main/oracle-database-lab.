#!/usr/bin/env bash
# scripts/lab5/07-divisiones-y-cola.sh — divisiones 50/50 y 90/10, índice REVERSE, patrón cola y sus remedios, con radiografía en cada paso
# Uso: bash scripts/lab5/07-divisiones-y-cola.sh
set -euo pipefail
source scripts/deployment/env/00-config.sh
TS=$(ts)
D="$EVID_LAB5/script"
bash scripts/ops/sysdba.sh scripts/lab5/07a-crecimiento.sql "$D/${TS}_07a-crecimiento.script.log"
for IDX in IX_AZAR IX_CRECIENTE IX_INVERTIDA; do bash scripts/ops/grafico-indice.sh LAB5_PRUEBAS "$IDX" "$D/${TS}_07a-grafico-${IDX}.script.log"; done
bash scripts/ops/sysdba.sh scripts/lab5/07b-patron-cola.sql "$D/${TS}_07b-patron-cola.script.log"
bash scripts/ops/grafico-indice.sh LAB5_PRUEBAS IX_COLA "$D/${TS}_07b-grafico-IX_COLA-antes.script.log"
bash scripts/ops/sysdba.sh scripts/lab5/07c-remedios.sql "$D/${TS}_07c-remedios.script.log"
bash scripts/ops/grafico-indice.sh LAB5_PRUEBAS IX_COLA "$D/${TS}_07c-grafico-IX_COLA-despues.script.log"
docker exec -i "$CONT_NAME" sqlplus -s -L / as sysdba <<'SQL' | tee -a "$D/${TS}_07c-remedios.script.log"
ALTER SESSION SET CONTAINER = FREEPDB1;
DROP USER lab5_pruebas CASCADE;
SELECT 'Esquema de pruebas LAB5_PRUEBAS borrado' AS limpieza FROM dual;
EXIT
SQL
