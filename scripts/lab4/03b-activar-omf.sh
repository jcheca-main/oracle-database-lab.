#!/usr/bin/env bash
# scripts/lab4/03b-activar-omf.sh — RETO de la Parte C: que un CREATE TABLESPACE sin DATAFILE
# (o con ruta relativa) no pueda volver a dejar archivos fuera de la carpeta estándar.
# Oracle Managed Files (OMF): si DB_CREATE_FILE_DEST está fijado, Oracle elige nombre y ubicación.
# Cambio de configuración -> SCOPE=BOTH (efectivo ya y tras el próximo arranque).
set -euo pipefail
source scripts/deployment/env/00-config.sh

echo "== 1. Activo OMF en FREEPDB1 =="
docker exec -i "$CONT_NAME" sqlplus -s -L / as sysdba <<'SQL'
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER SYSTEM SET db_create_file_dest = '/opt/oracle/oradata/FREE/FREEPDB1' SCOPE = BOTH;
SET LINESIZE 160 PAGESIZE 50 FEEDBACK OFF
SELECT SYS_CONTEXT('USERENV','CON_NAME') AS contenedor, name, display_value AS valor, ismodified
  FROM v$parameter WHERE name = 'db_create_file_dest';
EXIT
SQL

echo "== 2. Demostración: CREATE TABLESPACE sin cláusula DATAFILE =="
docker exec -i "$CONT_NAME" sqlplus -s -L / as sysdba <<'SQL'
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET LINESIZE 160 PAGESIZE 50 FEEDBACK ON
ALTER SESSION SET CONTAINER = FREEPDB1;
-- Sin OMF esto fallaría con ORA-02236 (missing path name); con OMF Oracle nombra el archivo solo
CREATE TABLESPACE tbs_prueba_omf;
SELECT tablespace_name, file_name, ROUND(bytes/1048576) AS mb, autoextensible
  FROM dba_data_files WHERE tablespace_name = 'TBS_PRUEBA_OMF';
DROP TABLESPACE tbs_prueba_omf INCLUDING CONTENTS AND DATAFILES;
SQL
echo "== 3. tbs_prueba_omf eliminado (también su archivo, por INCLUDING CONTENTS AND DATAFILES) =="
