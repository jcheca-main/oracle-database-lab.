#!/usr/bin/env bash
# scripts/ops/alumno.sh — tu código de alumno en el entorno (Lab 6, Parte A.3)
# Lee ESTUDIANTE de config/.env (E y tres dígitos: tu código de la lista de clase, p. ej. E017) y:
#   1) genera login.sql en la raíz del repositorio: SQLcl lo lee al conectar y pone tu código en el prompt
#   2) pone el mismo prompt al SQL*Plus del contenedor (docker exec ... sqlplus), en su glogin.sql
#   3) muestra la cabecera que llevará cada evidencia del Lab 6
# Repite este script si recreas el contenedor (el glogin.sql vive dentro de él, no en el volumen).
# Uso: bash scripts/ops/alumno.sh
set -euo pipefail
source scripts/deployment/env/00-config.sh
[ -f config/.env ] || { echo "Falta config/.env (Lab 4, Parte B)" >&2; exit 2; }
source config/.env
[[ "${ESTUDIANTE:-}" =~ ^E[0-9]{3}$ ]] \
  || { echo "ESTUDIANTE debe ser tu código de la lista de clase (E y tres dígitos, p. ej. E017) en config/.env" >&2; exit 2; }

echo "== 1. login.sql para SQLcl (raíz del repositorio) =="
cat > login.sql <<SQL
-- login.sql — GENERADO por scripts/ops/alumno.sh a partir de config/.env: no lo edites a mano
DEFINE ESTUDIANTE = $ESTUDIANTE
SET SQLPROMPT "$ESTUDIANTE _USER'@'_CONNECT_IDENTIFIER> "
SET TIME ON
SQL
cat login.sql
echo "SQLcl lo lee si arrancas 'sql' desde la raíz del repositorio (00-config.sh exporta SQLPATH=$(pwd))."

echo "== 2. El mismo prompt en el SQL*Plus del contenedor =="
docker exec -i "$CONT_NAME" bash -c '
f="$ORACLE_HOME/sqlplus/admin/glogin.sql"
sed -i "/^REM oralab-alumno inicio/,/^REM oralab-alumno fin/d" "$f"
cat >> "$f"
sed -n "/^REM oralab-alumno inicio/,/^REM oralab-alumno fin/p" "$f"' <<SQL
REM oralab-alumno inicio (scripts/ops/alumno.sh)
DEFINE ESTUDIANTE = $ESTUDIANTE
SET SQLPROMPT "$ESTUDIANTE _USER'@'_CONNECT_IDENTIFIER> "
SET TIME ON
REM oralab-alumno fin
SQL

echo "== 3. Cabecera de tus evidencias =="
bash scripts/ops/cabecera.sh alumno
echo "Listo: cada evidencia del Lab 6 empezará con estas dos líneas."
