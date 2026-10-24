#!/usr/bin/env bash
# scripts/lab4/09-procesos-so.sh — los mismos procesos vistos desde Linux, con el PID que ve Oracle (SPID)
# Ojo: `docker top` muestra PID del HOST; Oracle (v$process.spid) usa el PID DENTRO del contenedor
# (espacio de nombres de PID propio). Este script lee /proc dentro del contenedor, así los PID coinciden.
# La imagen no trae `ps`: /proc es la fuente que usan ps y top por debajo.
# Uso: bash scripts/lab4/09-procesos-so.sh [SPID]
set -euo pipefail
TMP=$(mktemp)
source scripts/deployment/env/00-config.sh
docker exec "$CONT_NAME" bash -c '
  printf "%-8s %-10s %s\n" PID RSS_MB PROCESO
  for d in /proc/[0-9]*; do
    pid=${d#/proc/}
    cmd=$(tr "\0" " " < "$d/cmdline" 2>/dev/null) || continue
    [ -n "$cmd" ] || continue
    rss=$(awk "/^VmRSS/ {printf \"%.0f\", \$2/1024}" "$d/status" 2>/dev/null)
    printf "%-8s %-10s %s\n" "$pid" "${rss:-0}" "$cmd"
  done' > "$TMP"
echo "== 1. Procesos de background clave (compara el PID con SPID de 09-procesos.sql) =="
grep -E '_(pmon|lreg|smon|dbw0|lgwr|ckpt|mmon|mmnl|reco)_' "$TMP"
echo "== 2. Recuento por tipo =="
echo "   background (db_*_FREE / ora_*_FREE): $(grep -cE ' (db|ora)_[a-z0-9]+_FREE' "$TMP")"
echo "   servidor dedicado (oracleFREE):       $(grep -c 'oracleFREE' "$TMP")"
echo "   listener (tnslsnr):                   $(grep -c 'tnslsnr' "$TMP")"
echo "== 3. Procesos servidor: LOCAL=NO llega por red (listener), LOCAL=YES es bequeath (docker exec ... / as sysdba) =="
grep 'oracleFREE' "$TMP" || echo "   (ninguno: abre una sesión SQLcl en otra terminal y repite)"
if [ -n "${1:-}" ]; then
  echo "== 4. El proceso con SPID $1 =="
  awk -v p="$1" '$1 == p' "$TMP"
fi
rm -f "$TMP"
