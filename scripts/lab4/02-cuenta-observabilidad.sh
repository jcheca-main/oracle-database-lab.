#!/usr/bin/env bash
# scripts/lab4/02-cuenta-observabilidad.sh — crea (o completa) la cuenta común de solo lectura C##OPS_RO
# La contraseña sale de config/.env y entra por la entrada estándar: no aparece en `ps` ni en el historial.
set -euo pipefail
source scripts/deployment/env/00-config.sh
[ -f config/.env ] || { echo "Falta config/.env: cópialo de config/.env.example (Parte B.1)"; exit 2; }
source config/.env
[ -n "${OPS_RO_PWD:-}" ] || { echo "Falta OPS_RO_PWD en config/.env (Parte B.1)"; exit 2; }
{ printf 'DEFINE ops_pwd = "%s"\n' "$OPS_RO_PWD"; cat scripts/lab4/02-cuenta-observabilidad.sql; } \
  | docker exec -i "$CONT_NAME" sqlplus -s -L / as sysdba
