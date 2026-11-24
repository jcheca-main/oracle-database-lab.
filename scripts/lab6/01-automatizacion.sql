-- scripts/lab6/01-automatizacion.sql — lo que Oracle hace por ti mientras nadie mira (Unidad 5, 5.1.5)
-- Solo lectura (C##OPS_RO) por el servicio de la PDB:  bash scripts/ops/ro.sh scripts/lab6/01-automatizacion.sql freepdb1
@scripts/ops/marca
@scripts/ops/cabecera 01-automatizacion
SPOOL docs/bitacora/lab6/evidencia/spool/&marca._01-automatizacion.spool.log
PROMPT &cab1
PROMPT &cab2
SET TERMOUT OFF
SET SQLFORMAT DEFAULT
SET TERMOUT ON
SET LINESIZE 160 PAGESIZE 100 FEEDBACK OFF
COLUMN client_name FORMAT A32
COLUMN valor FORMAT A20
COLUMN name FORMAT A32
COLUMN owner FORMAT A10
COLUMN window_group FORMAT A16
COLUMN window_name FORMAT A17
COLUMN repeat_interval FORMAT A70
COLUMN horas FORMAT 999
COLUMN enabled FORMAT A7
COLUMN tablespace FORMAT A14
COLUMN op FORMAT A12
COLUMN aviso FORMAT A13
COLUMN critico FORMAT A13
COLUMN snap_interval FORMAT A20
COLUMN retention FORMAT A20
COLUMN job_name FORMAT A30
COLUMN state FORMAT A10
PROMPT == 1. Tareas de mantenimiento automático (AutoTask) ==
SELECT client_name, status, window_group FROM dba_autotask_client ORDER BY client_name;
PROMPT == 2. Ventanas de mantenimiento: cuándo y cuántas horas duran ==
SELECT window_name, REPLACE(repeat_interval, ' ') AS repeat_interval,
       EXTRACT(DAY FROM duration) * 24 + EXTRACT(HOUR FROM duration) AS horas, enabled
  FROM dba_scheduler_windows ORDER BY window_name;
PROMPT == 3. Umbrales de las alertas de espacio (MMON) que rigen EN ESTA PDB ==
PROMPT (NONE = ningún umbral: MMON no avisará aunque el tablespace se llene; se arregla en la Parte F)
SELECT tablespace_name AS tablespace, warning_operator AS op,
       REPLACE(warning_value, '<SYSTEM-GENERATED THRESHOLD>', '(automático)') AS aviso,
       REPLACE(critical_value, '<SYSTEM-GENERATED THRESHOLD>', '(automático)') AS critico
  FROM dba_tablespace_thresholds
 WHERE tablespace_name IN ('SYSTEM', 'USERS', 'TBS_ACADEMIA', 'TBS_TIENDASUR', 'UNDOTBS1', 'TEMP')
 ORDER BY tablespace_name;
PROMPT == 4. AWR: cada cuánto toma fotos y cuánto las guarda ==
SELECT snap_interval, retention FROM dba_hist_wr_control WHERE con_id = SYS_CONTEXT('USERENV', 'CON_ID');
SELECT name, value AS valor FROM v$parameter WHERE name IN ('control_management_pack_access', 'statistics_level');
PROMPT == 5. Trabajos del Scheduler: cuántos hay y cuántos fallaron en 7 días ==
SELECT owner, COUNT(*) AS trabajos, SUM(CASE WHEN enabled = 'TRUE' THEN 1 ELSE 0 END) AS habilitados
  FROM dba_scheduler_jobs GROUP BY owner ORDER BY trabajos DESC FETCH FIRST 4 ROWS ONLY;
SELECT job_name, status, COUNT(*) AS ejecuciones
  FROM dba_scheduler_job_run_details
 WHERE log_date > SYSTIMESTAMP - INTERVAL '7' DAY AND status <> 'SUCCEEDED'
 GROUP BY job_name, status ORDER BY ejecuciones DESC FETCH FIRST 5 ROWS ONLY;
PROMPT (vacío en la última consulta = ningún trabajo falló en 7 días)
SPOOL OFF
