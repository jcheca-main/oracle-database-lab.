-- scripts/lab4/01-diagnostico-inicial.sql — radiografía de partida (SYSDBA, solo lectura)
SET LINESIZE 200 PAGESIZE 100 FEEDBACK OFF
COLUMN host_name FORMAT A14
COLUMN name FORMAT A62
COLUMN pdb FORMAT A10
COLUMN value FORMAT A40
PROMPT == 1. Instancia ==
SELECT instance_name, host_name, version_full, status, TO_CHAR(startup_time, 'YYYY-MM-DD HH24:MI') AS arranque
  FROM v$instance;
PROMPT == 2. Base de datos ==
SELECT name, cdb, log_mode, open_mode FROM v$database;
PROMPT == 3. Contenedores ==
SELECT con_id, name, open_mode FROM v$containers ORDER BY con_id;
PROMPT == 4. Datafiles de FREEPDB1 (fíjate en la RUTA de los tablespaces TBS_*) ==
SELECT d.file#, d.name, ROUND(d.bytes / 1024 / 1024) AS mb
  FROM v$datafile d JOIN v$pdbs p ON p.con_id = d.con_id
 WHERE p.name = 'FREEPDB1' ORDER BY d.file#;
PROMPT == 5. ¿Hay destino por defecto para archivos nuevos (OMF)? ==
SELECT name, NVL(value, '(vacío: sin OMF)') AS value FROM v$parameter
 WHERE name IN ('db_create_file_dest', 'db_recovery_file_dest');
EXIT
