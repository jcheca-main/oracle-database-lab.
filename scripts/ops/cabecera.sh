#!/usr/bin/env bash
# scripts/ops/cabecera.sh — cabecera de evidencia del Lab 6: quién, dónde y cuándo se generó esta salida
# La escriben, al empezar, todos los scripts del Lab 6 y los envoltorios ro.sh, app.sh y sysdba.sh (una vez por ejecución).
# Dos líneas: tu código de alumno, la hora UTC de la base y el script; después, el contenedor, el DBID, el arranque y el SCN.
# El docente las compara entre tus evidencias, con las de otros alumnos y con la hora del commit que sube cada archivo.
# Uso desde un script: source scripts/ops/cabecera.sh <origen>      ·   a mano: bash scripts/ops/cabecera.sh prueba
_cab_origen="${1:-manual}"
if [ -z "${CABECERA_HECHA:-}" ]; then
  [ -n "${CONT_NAME:-}" ] || source scripts/deployment/env/00-config.sh
  _cab_est=$(set -a; [ -f config/.env ] && . config/.env > /dev/null 2>&1; printf '%s' "${ESTUDIANTE:-}")
  if [[ ! "$_cab_est" =~ ^E[0-9]{3}$ ]]; then
    echo "ERROR: falta tu código de alumno. Pon ESTUDIANTE=\"E0NN\" (tu código de la lista de clase) en config/.env" >&2
    echo "       y ejecuta: bash scripts/ops/alumno.sh   (Lab 6, Parte A.3)" >&2
    unset _cab_origen _cab_est
    return 2 2> /dev/null || exit 2
  fi
  _cab_bd=$(printf '%s\n' "SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 300" \
    "SELECT 'hora=' || TO_CHAR(SYS_EXTRACT_UTC(SYSTIMESTAMP), 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') || ' contenedor=' || i.host_name || ' dbid=' || d.dbid || ' arranque=' || TO_CHAR(i.startup_time, 'YYYY-MM-DD\"T\"HH24:MI:SS') || ' scn=' || d.current_scn FROM v\$instance i, v\$database d;" \
    | docker exec -i -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 "$CONT_NAME" sqlplus -s -L / as sysdba 2> /dev/null | awk '/^hora=/ && !v {print; v=1}') || _cab_bd=''
  if [ -n "$_cab_bd" ]; then
    echo "== EVIDENCIA alumno=$_cab_est ${_cab_bd%% *} origen=$_cab_origen"
    echo "== EVIDENCIA ${_cab_bd#* }"
  else
    echo "== EVIDENCIA alumno=$_cab_est hora=$(date -u +%Y-%m-%dT%H:%M:%SZ) origen=$_cab_origen"
    echo "== EVIDENCIA base=no-disponible (hora de Ubuntu: la base no respondía)"
  fi
  export CABECERA_HECHA=1
  unset _cab_est _cab_bd
fi
unset _cab_origen
