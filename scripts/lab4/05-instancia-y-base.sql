-- scripts/lab4/05-instancia-y-base.sql — instancia frente a base de datos (SQLcl · C##OPS_RO · servicio FREE)
@scripts/ops/marca
SPOOL docs/bitacora/lab4/evidencia/spool/&marca._05-instancia-y-base.spool.log
SET SQLFORMAT DEFAULT
SET LINESIZE 180 PAGESIZE 100 FEEDBACK OFF
COLUMN host_name FORMAT A14
COLUMN contenedor FORMAT A10
COLUMN servicio FORMAT A12
COLUMN usuario FORMAT A12
COLUMN sid FORMAT A6
COLUMN name FORMAT A16
COLUMN network_name FORMAT A16
COLUMN platform_name FORMAT A22
PROMPT == 1. La INSTANCIA: procesos + memoria, vive mientras está arrancada ==
SELECT instance_name, host_name, version_full, status, database_status,
       TO_CHAR(startup_time, 'YYYY-MM-DD HH24:MI:SS') AS arrancada
  FROM v$instance;
PROMPT == 2. La BASE DE DATOS: archivos en disco, existe aunque la instancia esté parada ==
SELECT dbid, name, db_unique_name, cdb, log_mode, open_mode, platform_name,
       TO_CHAR(created, 'YYYY-MM-DD') AS creada
  FROM v$database;
PROMPT == 3. ¿Dónde estoy y con quién? ==
SELECT SYS_CONTEXT('USERENV', 'CON_NAME')     AS contenedor,
       SYS_CONTEXT('USERENV', 'SERVICE_NAME') AS servicio,
       SYS_CONTEXT('USERENV', 'SESSION_USER') AS usuario,
       SYS_CONTEXT('USERENV', 'SID')          AS sid
  FROM dual;
PROMPT == 4. Servicios que la instancia ofrece (LREG los registra en el listener) ==
SELECT con_id, name, network_name FROM v$services ORDER BY con_id, name;
PROMPT == 5. Los archivos que forman la base de datos ==
SELECT 'datafiles' AS tipo, COUNT(*) AS n, ROUND(SUM(bytes) / 1048576) AS mb FROM v$datafile
UNION ALL SELECT 'tempfiles', COUNT(*), ROUND(SUM(bytes) / 1048576) FROM v$tempfile
UNION ALL SELECT 'redo (miembros)', COUNT(*), NULL FROM v$logfile
UNION ALL SELECT 'control files', COUNT(*), NULL FROM v$controlfile;
SPOOL OFF
