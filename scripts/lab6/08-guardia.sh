#!/usr/bin/env bash
# scripts/lab6/08-guardia.sh — guardia nocturna en Academia: genera incidentes reales para practicar el método (Unidad 5, 5.7.7 y 5.7.8)
# Uso:  bash scripts/lab6/08-guardia.sh incidente 1|2|3     abre un incidente y muestra SOLO el ticket (como en la vida real)
#       bash scripts/lab6/08-guardia.sh limpiar             emergencia: deja el entorno como antes de la guardia
# No leas este archivo antes de resolver los incidentes: el ticket es todo lo que sabría el DBA de guardia.
set -euo pipefail
export LC_ALL=C.UTF-8
source scripts/deployment/env/00-config.sh
source scripts/ops/cabecera.sh "08-guardia-${1:-}${2:-}" || exit 2   # Lab 6: cabecera de evidencia (alumno, hora, contenedor, SCN)
source config/.env
sql() { docker exec -i -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 "$CONT_NAME" sqlplus -s -L / as sysdba; }
ticket() {   # recuadro de 78 columnas; ${#l} cuenta caracteres (no bytes), así los acentos no descuadran
  local raya l; raya=$(printf '%*s' 76 '' | tr ' ' '-')
  echo; echo "+$raya+"
  for l in "$@"; do printf '| %s%*s |\n' "$l" $((74 - ${#l})) ''; done
  echo "+$raya+"; echo
}

# Lanza una sesión de base de datos que sigue viva cuando este script termina (como la de una aplicación real)
sesion_fondo() {   # $1 = usuario, $2 = contraseña, $3 = servicio, $4 = SQL
  setsid nohup bash -c 'printf "%s\n" "$1" | docker exec -i -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 "$2" sqlplus -s /nolog > /dev/null 2>&1' _ \
    "$(printf 'CONNECT %s/"%s"@//localhost:1521/%s\n%s\nEXIT' "$1" "$2" "$3" "$4")" "$CONT_NAME" > /dev/null 2>&1 &
}

case "${1:-} ${2:-}" in
  "incidente 1")
    # La aplicación de matrículas deja una transacción abierta sobre la fila 101 y se queda esperando 15 minutos
    sesion_fondo app_academia "$APP_ACADEMIA_PWD" academia_app "EXEC DBMS_APPLICATION_INFO.SET_MODULE('matriculas', 'cierre-periodo')
UPDATE admin_academia.aca_estudiantes SET estado = 'EGRESADO' WHERE estudiante_id = 101;
EXEC DBMS_SESSION.SLEEP(900)
ROLLBACK;"
    sleep 4
    # Ana, de secretaría, intenta guardar la ficha del mismo alumno
    sesion_fondo ana_garcia "$ANA_GARCIA_PWD" freepdb1 "EXEC DBMS_APPLICATION_INFO.SET_MODULE('secretaria', 'ficha-alumno')
UPDATE admin_academia.aca_estudiantes SET estado = 'ACTIVO' WHERE estudiante_id = 101;
COMMIT;"
    sleep 3
    ticket "TICKET INC-601 · prioridad ALTA · $(date -u +%H:%M) UTC" \
           "Secretaría (Ana García): «Al guardar la ficha del alumno 101 la pantalla" \
           "se queda colgada. Ya he reiniciado mi ordenador dos veces»." \
           "Base afectada: FREEPDB1 (Academia)." ;;
  "incidente 2")
    printf "ALTER SESSION SET CONTAINER = FREEPDB1;\nEXEC DBMS_SERVICE.STOP_SERVICE('academia_app')\nEXIT\n" | sql > /dev/null
    ticket "TICKET INC-602 · prioridad CRÍTICA · $(date -u +%H:%M) UTC" \
           "Equipo de matrículas: «Desde hace unos minutos ninguna instancia de la" \
           "aplicación conecta. El error dice: ORA-12514. ¿Está caída la base?»" ;;
  "incidente 3")
    printf "ALTER SESSION SET CONTAINER = FREEPDB1;\nALTER USER app_academia ACCOUNT LOCK;\nEXIT\n" | sql > /dev/null
    ticket "TICKET INC-603 · prioridad ALTA · $(date -u +%H:%M) UTC" \
           "Equipo de matrículas: «Tras el despliegue de las 21:00, la aplicación no" \
           "entra: ORA-28000. No hemos cambiado la contraseña»." \
           "Nota del turno de tarde: hoy se ejecutó el script trimestral de bajas." ;;
  "limpiar "*)
    sql <<'SQL'
SET FEEDBACK OFF
ALTER SESSION SET CONTAINER = FREEPDB1;
SET SERVEROUTPUT ON
BEGIN
  FOR s IN (SELECT sid, serial# FROM v$session WHERE username IN ('APP_ACADEMIA', 'ANA_GARCIA')) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'ALTER SYSTEM KILL SESSION ''' || s.sid || ',' || s.serial# || ''' IMMEDIATE';
    EXCEPTION WHEN OTHERS THEN
      IF SQLCODE NOT IN (-31, -30) THEN RAISE; END IF;   -- ORA-00031 marcada / ORA-00030 ya no existe: es lo que queremos
    END;
    DBMS_OUTPUT.PUT_LINE('Sesión ' || s.sid || ' terminada');
  END LOOP;
  FOR x IN (SELECT 1 FROM dual WHERE NOT EXISTS (SELECT 1 FROM v$active_services WHERE name = 'academia_app')) LOOP
    DBMS_SERVICE.START_SERVICE('academia_app'); DBMS_OUTPUT.PUT_LINE('Servicio academia_app arrancado');
  END LOOP;
END;
/
ALTER USER app_academia ACCOUNT UNLOCK;
ALTER PLUGGABLE DATABASE FREEPDB1 SAVE STATE;
UPDATE admin_academia.aca_estudiantes SET estado = 'ACTIVO' WHERE estudiante_id = 101 AND estado <> 'ACTIVO';
COMMIT;
PROMPT Entorno de la guardia restablecido
SQL
    ;;
  *) echo "Uso: $0 incidente 1|2|3  |  $0 limpiar" >&2; exit 2 ;;
esac
