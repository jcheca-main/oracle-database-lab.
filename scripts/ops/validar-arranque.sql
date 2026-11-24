-- scripts/ops/validar-arranque.sql — «arriba» exige evidencia (Unidad 5, 5.2.8). Solo lectura, C##OPS_RO.
-- Desde la raíz:            bash scripts/ops/ro.sh scripts/ops/validar-arranque.sql
-- Por el servicio de la PDB: bash scripts/ops/ro.sh scripts/ops/validar-arranque.sql freepdb1
SET TERMOUT OFF
SET SQLFORMAT DEFAULT
SET TERMOUT ON
SET LINESIZE 160 PAGESIZE 100 FEEDBACK OFF
COLUMN instance_name FORMAT A10
COLUMN name FORMAT A16
COLUMN estado_guardado FORMAT A22
COLUMN error FORMAT A9
COLUMN veces FORMAT 99999
COLUMN ejemplo FORMAT A85
COLUMN contenedor FORMAT A12
COLUMN servicio FORMAT A16
PROMPT == 0. Por dónde he entrado ==
SELECT SYS_CONTEXT('USERENV','CON_NAME') AS contenedor, SYS_CONTEXT('USERENV','SERVICE_NAME') AS servicio FROM dual;
PROMPT == 1. Instancia y base ==
SELECT instance_name, status, logins, TO_CHAR(startup_time, 'YYYY-MM-DD HH24:MI') AS arranque FROM v$instance;
SELECT name, open_mode, log_mode, database_role FROM v$database;
PROMPT == 2. Cada PDB en el modo esperado (y si tiene estado guardado) ==
SELECT p.name, p.open_mode, p.restricted, NVL(s.state, '(sin estado guardado)') AS estado_guardado
  FROM v$pdbs p LEFT JOIN cdb_pdb_saved_states s ON s.con_name = p.name ORDER BY p.con_id;
PROMPT == 3. Servicios activos (deben estar los de cada PDB abierta) ==
SELECT con_id, name FROM v$active_services WHERE name NOT LIKE 'SYS$%' ORDER BY con_id, name;
PROMPT == 4. Errores ORA- en el alert log desde el último arranque, agrupados (compáralos con los de siempre) ==
SELECT REGEXP_SUBSTR(message_text, 'ORA-[0-9]{5}') AS error, COUNT(*) AS veces,
       SUBSTR(MIN(REGEXP_SUBSTR(message_text, 'ORA-[0-9]{5}[^' || CHR(10) || ']*')), 1, 85) AS ejemplo
  FROM v$diag_alert_ext
 WHERE originating_timestamp >= (SELECT CAST(startup_time AS TIMESTAMP) FROM v$instance)
   AND message_text LIKE '%ORA-%'
 GROUP BY REGEXP_SUBSTR(message_text, 'ORA-[0-9]{5}') ORDER BY veces DESC, error;
PROMPT == 5. Datafiles que no están ONLINE (vacío = bien) ==
SELECT file#, status, name FROM v$datafile WHERE status NOT IN ('ONLINE', 'SYSTEM');
