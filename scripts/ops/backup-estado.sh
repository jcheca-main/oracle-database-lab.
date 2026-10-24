#!/usr/bin/env bash
# scripts/ops/backup-estado.sh — copia en frío y consistente del estado del laboratorio.
# Copia el volumen completo y, si los hay, los archivos de la base que viven FUERA del volumen.
# Uso: bash scripts/ops/backup-estado.sh <etiqueta-en-kebab-case>     (p. ej.: lab3-final)
set -euo pipefail
source scripts/deployment/env/00-config.sh
docker info > /dev/null 2>&1 || { echo "ERROR: Docker no responde (¿está arrancado Docker Desktop o el servicio docker?). No se ha tocado nada." >&2; exit 1; }

ETIQUETA="${1:?Uso: backup-estado.sh <etiqueta, p. ej. lab3-final>}"
[[ "$ETIQUETA" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "La etiqueta debe ir en kebab-case (p. ej. lab3-final)"; exit 2; }
DEST="$BACKUP_DIR/$(ts)_$ETIQUETA"
DUENO="$(id -u):$(id -g)"

echo "== 1. Comprobaciones previas =="
docker volume inspect "$VOL_NAME" > /dev/null || { echo "No existe el volumen $VOL_NAME"; exit 1; }
[ "$(docker inspect -f '{{.State.Running}}' "$CONT_NAME")" = "true" ] \
  || { echo "El contenedor debe estar en marcha: docker start $CONT_NAME"; exit 1; }
mkdir -p "$DEST/extras"
USADO=$(docker run --rm -v "$VOL_NAME":/v:ro "$HELPER_IMG" du -sm /v | cut -f1)
LIBRE=$(df -Pm "$BACKUP_DIR" | awk 'NR==2 {print $4}')
echo "Volumen: ${USADO} MB · libre en backups/: ${LIBRE} MB"
[ "$LIBRE" -gt "$USADO" ] || { echo "Espacio insuficiente para la copia"; exit 1; }

echo "== 2. Inventario de archivos (base abierta) =="
docker exec -i "$CONT_NAME" sqlplus -s -L / as sysdba \
  < scripts/ops/inventario-archivos.sql > "$DEST/inventario.txt"
cat "$DEST/inventario.txt"

echo "== 3. Cobertura: ¿está todo dentro de $DATA_ROOT (el volumen)? =="
: > "$DEST/extras.lst"
grep '^FILE|' "$DEST/inventario.txt" | cut -d'|' -f3 | sort -u | while read -r f; do
  real=$(docker exec "$CONT_NAME" readlink -f "$f")
  if [[ "$real" == "$DATA_ROOT"/* ]]; then
    echo "  dentro  $f"
  else
    echo "  FUERA   $f"
    echo "$real" >> "$DEST/extras.lst"
  fi
done

# Pase lo que pase a partir de aquí, el contenedor vuelve a arrancar al terminar.
trap 'echo "== Arranque del contenedor =="; docker start "$CONT_NAME" > /dev/null' EXIT

echo "== 4. Parada limpia: SHUTDOWN IMMEDIATE y docker stop =="
echo "SHUTDOWN IMMEDIATE" | docker exec -i "$CONT_NAME" sqlplus -s -L / as sysdba
docker stop -t 120 "$CONT_NAME" > /dev/null

echo "== 5. Copia del volumen (tar + gzip, conservando dueños y permisos) =="
docker run --rm -v "$VOL_NAME":/origen:ro -v "$DEST":/destino "$HELPER_IMG" \
  sh -c "tar --numeric-owner -czpf /destino/volumen.tar.gz -C /origen . && chown $DUENO /destino/volumen.tar.gz"

echo "== 6. Archivos fuera del volumen =="
n=0
while read -r f; do
  [ -n "$f" ] || continue
  n=$((n + 1))
  docker cp "$CONT_NAME:$f" - | gzip > "$DEST/extras/extra_$n.tar.gz"
  echo "extra_$n.tar.gz|$f" >> "$DEST/extras/mapa.txt"
  echo "  copiado $f"
done < "$DEST/extras.lst"
[ "$n" -eq 0 ] && echo "  ninguno: el volumen contiene toda la base de datos"

echo "== 7. Manifiesto y sumas SHA-256 =="
{
  echo "etiqueta=$ETIQUETA"
  echo "fecha_utc=$(ts)"
  echo "contenedor=$CONT_NAME"
  echo "volumen=$VOL_NAME"
  echo "imagen=$(docker inspect -f '{{.Config.Image}}' "$CONT_NAME")"
  echo "git_commit=$(git rev-parse --short HEAD 2> /dev/null || echo n/a)"
  echo "tipo=copia en frio consistente (SHUTDOWN IMMEDIATE)"
  echo "archivos_fuera_del_volumen=$n"
} > "$DEST/manifiesto.txt"
(cd "$DEST" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)

trap - EXIT
echo "== 8. Arranque y espera a healthy =="
docker start "$CONT_NAME" > /dev/null
bash scripts/ops/esperar-healthy.sh

echo "== Copia terminada =="
du -sh "$DEST"
echo "Para restaurarla: bash scripts/ops/restaurar-estado.sh $DEST"
