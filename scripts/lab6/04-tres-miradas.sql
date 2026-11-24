-- scripts/lab6/04-tres-miradas.sql — la MISMA consulta, tres identidades (Unidad 5, 5.4.3.1)
-- Lo ejecuta 04-tres-miradas.sh con C##OPS_RO en la raíz, C##OPS_RO en FREEPDB1 y APP_ACADEMIA por academia_app.
SET TERMOUT OFF
SET SQLFORMAT DEFAULT
SET TERMOUT ON
SET LINESIZE 120 PAGESIZE 50 FEEDBACK OFF
COLUMN usuario FORMAT A14
COLUMN contenedor FORMAT A10
COLUMN vista FORMAT A30
SELECT USER AS usuario, SYS_CONTEXT('USERENV', 'CON_NAME') AS contenedor FROM dual;
SELECT 'USER_TABLES (lo mío)' AS vista, COUNT(*) AS filas FROM user_tables
UNION ALL SELECT 'ALL_TABLES de ADMIN_ACADEMIA', COUNT(*) FROM all_tables WHERE owner = 'ADMIN_ACADEMIA'
UNION ALL SELECT 'ALL_USERS (los que veo)', COUNT(*) FROM all_users;
PROMPT -- DBA_USERS (todo el contenedor actual):
SELECT COUNT(*) AS dba_users FROM dba_users;
PROMPT -- CDB_USERS por contenedor (todos los contenedores que tengo permitido ver):
SELECT con_id, COUNT(*) AS cdb_users FROM cdb_users GROUP BY con_id ORDER BY con_id;
PROMPT -- V$DATAFILE (datafiles visibles):
SELECT COUNT(*) AS datafiles FROM v$datafile;
