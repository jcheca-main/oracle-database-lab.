#!/usr/bin/env bash
# scripts/lab6/02-pfile-so.sh — prepara la carpeta de las copias de texto y, después, las compara y guarda como evidencia
# Uso: bash scripts/lab6/02-pfile-so.sh preparar     (antes de 02-parametros.sql)
#      bash scripts/lab6/02-pfile-so.sh comparar     (después)
set -euo pipefail
source scripts/deployment/env/00-config.sh
source scripts/ops/cabecera.sh "$(basename "$0" .sh)" || exit 2   # Lab 6: cabecera de evidencia (alumno, hora, contenedor, SCN)
DIR="$DATA_ROOT/lab6"
case "${1:-}" in
  preparar)
    # La carpeta la crea el usuario oracle DENTRO del contenedor: las rutas de CREATE PFILE se resuelven en el servidor
    docker exec "$CONT_NAME" mkdir -p "$DIR"
    docker exec "$CONT_NAME" ls -ld "$DIR" ;;
  comparar)
    mkdir -p "$EVID_LAB6/config"
    docker exec "$CONT_NAME" wc -l "$DIR/init_desde_spfile.ora" "$DIR/init_desde_memoria.ora"
    echo "== Líneas del PFILE creado desde el SPFILE (lo que alguien fijó) =="
    docker exec "$CONT_NAME" cat "$DIR/init_desde_spfile.ora"
    docker cp "$CONT_NAME:$DIR/init_desde_spfile.ora" "$EVID_LAB6/config/$(ts)_02-init_desde_spfile.ora"
    docker cp "$CONT_NAME:$DIR/init_desde_memoria.ora" "$EVID_LAB6/config/$(ts)_02-init_desde_memoria.ora"
    echo "Copias guardadas en $EVID_LAB6/config/" ;;
  *) echo "Uso: $0 preparar|comparar" >&2; exit 2 ;;
esac
