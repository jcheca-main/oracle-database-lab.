-- scripts/ops/turno.sql — lista de turno (Unidad 5, 5.1.4.1): siete preguntas, siete respuestas, una evidencia
-- Solo lectura. La ejecuta C##OPS_RO desde la raíz:  bash scripts/ops/ro.sh scripts/ops/turno.sql
SET TERMOUT OFF
SET SQLFORMAT DEFAULT
SET TERMOUT ON
SET LINESIZE 150 PAGESIZE 100 FEEDBACK OFF
COLUMN contenedor FORMAT A12
COLUMN usuario FORMAT A12
COLUMN instancia FORMAT A10
COLUMN name FORMAT A10
COLUMN open_mode FORMAT A10
COLUMN log_mode FORMAT A10
COLUMN restricted FORMAT A10
COLUMN pdb FORMAT A10
COLUMN tablespace FORMAT A20
PROMPT == 1. ¿Dónde estoy y quién soy? ==
SELECT SYS_CONTEXT('USERENV','CON_NAME') AS contenedor, SYS_CONTEXT('USERENV','SESSION_USER') AS usuario,
       TO_CHAR(SYS_EXTRACT_UTC(SYSTIMESTAMP), 'YYYY-MM-DD HH24:MI') || ' UTC' AS ahora FROM dual;
PROMPT == 2. ¿Instancia y base están como deben? ==
SELECT instance_name AS instancia, status AS estado, logins,
       TO_CHAR(startup_time, 'YYYY-MM-DD HH24:MI') AS arranque FROM v$instance;
SELECT name, open_mode, log_mode FROM v$database;
PROMPT == 3. ¿Están abiertas las PDB? ==
SELECT con_id, name, open_mode, restricted FROM v$pdbs ORDER BY con_id;
PROMPT == 4. ¿Cuántos errores ORA- hay en el alert log en las últimas 24 h? (compáralo con tu línea base) ==
SELECT COUNT(*) AS errores_ora_24h FROM v$diag_alert_ext
 WHERE originating_timestamp > SYSTIMESTAMP - INTERVAL '1' DAY AND message_text LIKE '%ORA-%';
PROMPT == 5. ¿Algún tablespace por encima del 85 % de su máximo? (vacío = bien) ==
SELECT c.name AS pdb, m.tablespace_name AS tablespace, ROUND(m.used_percent, 1) AS pct_usado
  FROM cdb_tablespace_usage_metrics m JOIN v$containers c ON c.con_id = m.con_id
 WHERE m.used_percent > 85 ORDER BY m.used_percent DESC;
PROMPT == 6. ¿Hay sesiones bloqueadas ahora mismo? ==
SELECT COUNT(*) AS sesiones_bloqueadas FROM v$session WHERE blocking_session IS NOT NULL;
PROMPT == 7. ¿Hay alertas del servidor pendientes? ==
SELECT COUNT(*) AS alertas_pendientes FROM dba_outstanding_alerts;
