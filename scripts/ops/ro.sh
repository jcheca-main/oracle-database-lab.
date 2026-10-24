#!/usr/bin/env bash
# scripts/ops/ro.sh — ejecuta un script con SQLcl como C##OPS_RO (solo lectura) y termina.
# La contraseña viaja por la entrada estándar (printf es interno de bash): no aparece en `ps` ni en el historial.
# Uso: bash scripts/ops/ro.sh <archivo.sql> [servicio]     (servicio por defecto: FREE, la raíz del CDB)
set -euo pipefail
source scripts/deployment/env/00-config.sh
[ -f config/.env ] || { echo "Falta config/.env (cópialo de config/.env.example y rellena OPS_RO_PWD: Lab 4, Parte B)" >&2; exit 2; }
source config/.env
[ -n "${OPS_RO_PWD:-}" ] || { echo "OPS_RO_PWD está vacío en config/.env (Lab 4, Parte B)" >&2; exit 2; }
command -v sql > /dev/null || { echo "No encuentro SQLcl (comando sql) en el PATH: es el cliente que instalaste en el Lab 3" >&2; exit 2; }
mkdir -p docs/bitacora/lab4/evidencia/spool docs/bitacora/lab5/evidencia/spool   # destino de los SPOOL
SQL_FILE="${1:?Uso: ro.sh <archivo.sql> [servicio]}"
SERVICE="${2:-$SERVICE_CDB}"
[ -f "$SQL_FILE" ] || { echo "No existe $SQL_FILE" >&2; exit 2; }
printf 'CONNECT c##ops_ro/"%s"@//localhost:%s/%s\n@%s\nEXIT\n' \
  "$OPS_RO_PWD" "$PORT_DB" "$SERVICE" "$SQL_FILE" | sql -S /nolog
