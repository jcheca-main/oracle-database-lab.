#!/usr/bin/env bash
# scripts/lab6/06-cascada.sh — WITH ADMIN OPTION frente a WITH GRANT OPTION al revocar (Unidad 5, 5.6.5.2)
# Crea dos usuarios efímeros (U6_A y U6_B) con contraseñas aleatorias que solo existen durante el script, y los borra al final.
# Uso: bash scripts/lab6/06-cascada.sh | tee "$EVID_LAB6/script/$(ts)_06-cascada.script.log"
set -euo pipefail
source scripts/deployment/env/00-config.sh
source scripts/ops/cabecera.sh "$(basename "$0" .sh)" || exit 2   # Lab 6: cabecera de evidencia (alumno, hora, contenedor, SCN)
sql() { docker exec -i -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 "$CONT_NAME" sqlplus -s -L / as sysdba; }
PWD_A="U6a_$(date +%s%N | sha256sum | cut -c1-12)"; PWD_B="U6b_$(date +%s%N | sha256sum | cut -c1-12)"
VER="SET LINESIZE 120 PAGESIZE 50 FEEDBACK OFF
COLUMN grantee FORMAT A7
COLUMN grantor FORMAT A15
COLUMN privilege FORMAT A15
COLUMN table_name FORMAT A16
SELECT grantee, privilege, admin_option FROM dba_sys_privs WHERE grantee IN ('U6_A', 'U6_B') ORDER BY grantee;
SELECT grantee, grantor, table_name, privilege, grantable FROM dba_tab_privs WHERE grantee IN ('U6_A', 'U6_B') ORDER BY grantee;
SELECT COUNT(*) AS privilegios_de_objeto FROM dba_tab_privs WHERE grantee IN ('U6_A', 'U6_B');"
echo "== 1. Montaje: el DBA concede a U6_A un privilegio de SISTEMA con ADMIN OPTION y uno de OBJETO con GRANT OPTION =="
sql <<SQL
WHENEVER SQLERROR EXIT FAILURE
SET FEEDBACK ON
ALTER SESSION SET CONTAINER = FREEPDB1;
BEGIN
  FOR u IN (SELECT username FROM dba_users WHERE username IN ('U6_A', 'U6_B')) LOOP
    EXECUTE IMMEDIATE 'DROP USER ' || u.username || ' CASCADE';
  END LOOP;
END;
/
CREATE USER u6_a IDENTIFIED BY "$PWD_A";
CREATE USER u6_b IDENTIFIED BY "$PWD_B";
GRANT CREATE SESSION TO u6_a WITH ADMIN OPTION;
GRANT SELECT ON admin_academia.aca_asignaturas TO u6_a WITH GRANT OPTION;
SQL
echo "== 2. U6_A reparte lo recibido a U6_B =="
docker exec -i -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 "$CONT_NAME" sqlplus -s /nolog <<SQL
WHENEVER SQLERROR EXIT FAILURE
SET FEEDBACK ON
CONNECT u6_a/"$PWD_A"@//localhost:1521/freepdb1
GRANT CREATE SESSION TO u6_b;
GRANT SELECT ON admin_academia.aca_asignaturas TO u6_b;
SQL
echo "== 3. Antes de revocar a U6_A =="
{ echo "ALTER SESSION SET CONTAINER = FREEPDB1;"; echo "$VER"; } | sql
echo "== 4. El DBA revoca a U6_A los dos privilegios =="
sql <<'SQL'
SET FEEDBACK ON
ALTER SESSION SET CONTAINER = FREEPDB1;
REVOKE CREATE SESSION FROM u6_a;
REVOKE SELECT ON admin_academia.aca_asignaturas FROM u6_a;
SQL
echo "== 5. Después: el de SISTEMA de U6_B sobrevive; el de OBJETO de U6_B cae en cascada =="
{ echo "ALTER SESSION SET CONTAINER = FREEPDB1;"; echo "$VER"; } | sql
echo "== 6. Limpieza: los usuarios de prueba se borran (el ciclo de vida también incluye la baja) =="
printf "ALTER SESSION SET CONTAINER = FREEPDB1;\nDROP USER u6_a CASCADE;\nDROP USER u6_b CASCADE;\nEXIT\n" | sql
