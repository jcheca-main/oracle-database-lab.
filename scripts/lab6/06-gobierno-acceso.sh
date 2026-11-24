#!/usr/bin/env bash
# scripts/lab6/06-gobierno-acceso.sh — aplica 06-gobierno-acceso.sql con la contraseña inicial de ANA_GARCIA (config/.env)
set -euo pipefail
source scripts/deployment/env/00-config.sh
source scripts/ops/cabecera.sh "$(basename "$0" .sh)" || exit 2   # Lab 6: cabecera de evidencia (alumno, hora, contenedor, SCN)
source config/.env
[ -n "${ANA_GARCIA_PWD:-}" ] || { echo "Falta ANA_GARCIA_PWD en config/.env (Parte A.3)" >&2; exit 2; }
{ printf 'DEFINE ana_pwd = "%s"\n' "$ANA_GARCIA_PWD"; cat scripts/lab6/06-gobierno-acceso.sql; } \
  | docker exec -i -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 "$CONT_NAME" sqlplus -s -L / as sysdba
