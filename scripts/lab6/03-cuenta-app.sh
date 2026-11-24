#!/usr/bin/env bash
# scripts/lab6/03-cuenta-app.sh — crea (o realinea) APP_ACADEMIA con la contraseña de config/.env
set -euo pipefail
source scripts/deployment/env/00-config.sh
source scripts/ops/cabecera.sh "$(basename "$0" .sh)" || exit 2   # Lab 6: cabecera de evidencia (alumno, hora, contenedor, SCN)
[ -f config/.env ] || { echo "Falta config/.env" >&2; exit 2; }
source config/.env
[ -n "${APP_ACADEMIA_PWD:-}" ] || { echo "Falta APP_ACADEMIA_PWD en config/.env (Parte A.3)" >&2; exit 2; }
{ printf 'DEFINE app_pwd = "%s"\n' "$APP_ACADEMIA_PWD"; cat scripts/lab6/03-cuenta-app.sql; } \
  | docker exec -i -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 "$CONT_NAME" sqlplus -s -L / as sysdba
