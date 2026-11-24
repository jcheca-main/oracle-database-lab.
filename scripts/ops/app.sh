#!/usr/bin/env bash
# scripts/ops/app.sh — ejecuta un .sql como la cuenta de aplicación APP_ACADEMIA por el servicio academia_app (Lab 6).
# Valida el CAMINO REAL del consumidor: cliente -> listener -> servicio -> sesión (Unidad 5, 5.3).
# La contraseña viaja por la entrada estándar (no aparece en `ps` ni en el historial).
# Uso: bash scripts/ops/app.sh <archivo.sql> [servicio]     (servicio por defecto: academia_app)
set -euo pipefail
source scripts/deployment/env/00-config.sh
[ -f config/.env ] || { echo "Falta config/.env (Lab 4, Parte B)" >&2; exit 2; }
source config/.env
[ -n "${APP_ACADEMIA_PWD:-}" ] || { echo "APP_ACADEMIA_PWD está vacío en config/.env (Lab 6, Parte A.3)" >&2; exit 2; }
command -v sql > /dev/null || { echo "No encuentro SQLcl (comando sql) en el PATH" >&2; exit 2; }
SQL_FILE="${1:?Uso: app.sh <archivo.sql> [servicio]}"
SERVICE="${2:-academia_app}"
[ -f "$SQL_FILE" ] || { echo "No existe $SQL_FILE" >&2; exit 2; }
source scripts/ops/cabecera.sh "$(basename "$SQL_FILE" .sql)"   # Lab 6: cabecera de evidencia (una vez por ejecución)
printf 'DEFINE ESTUDIANTE = %s\nCONNECT app_academia/"%s"@//localhost:%s/%s\n@%s\nEXIT\n' \
  "${ESTUDIANTE:-SIN-CODIGO}" "$APP_ACADEMIA_PWD" "$PORT_DB" "$SERVICE" "$SQL_FILE" | sql -S /nolog
