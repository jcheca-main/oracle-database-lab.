-- scripts/lab5/15-healthcheck.sql — runbook de salud diaria (SQLcl · C##OPS_RO · servicio FREE)
-- Lo que un DBA/SRE revisa cada mañana, en un minuto y sin privilegios de escritura.
@scripts/ops/marca
SPOOL docs/bitacora/lab5/evidencia/spool/&marca._15-healthcheck.spool.log
SET SQLFORMAT DEFAULT
SET LINESIZE 170 PAGESIZE 100 FEEDBACK OFF
COLUMN comprobacion FORMAT A34
COLUMN valor FORMAT A40
COLUMN contenedor FORMAT A10
COLUMN tablespace_name FORMAT A14
COLUMN mensaje FORMAT A90
COLUMN resource_name FORMAT A22
COLUMN owner FORMAT A16
COLUMN ejemplo FORMAT A24
COLUMN problema FORMAT A30
COLUMN input_type FORMAT A14
COLUMN status FORMAT A10
PROMPT
PROMPT == 1. Disponibilidad ==
SELECT 'Instancia' AS comprobacion, status || ' desde ' || TO_CHAR(startup_time, 'YYYY-MM-DD HH24:MI') AS valor FROM v$instance
UNION ALL SELECT 'Base de datos', open_mode || ' · ' || log_mode FROM v$database
UNION ALL SELECT 'PDB ' || name, open_mode FROM v$pdbs WHERE name <> 'PDB$SEED';
PROMPT
PROMPT == 2. Espacio: tablespaces por encima del 80 % (vacío = bien) ==
SELECT c.name AS contenedor, m.tablespace_name, ROUND(m.used_percent, 1) AS usado_pct
  FROM cdb_tablespace_usage_metrics m JOIN v$containers c ON c.con_id = m.con_id
 WHERE m.used_percent > 80 ORDER BY m.used_percent DESC;
PROMPT
PROMPT == 3. Recuperabilidad: FRA y último archivado ==
SELECT 'FRA usada' AS comprobacion,
       ROUND(space_used / 1048576) || ' de ' || ROUND(space_limit / 1048576) || ' MB ('
       || ROUND(100 * space_used / NULLIF(space_limit, 0), 1) || ' %)' AS valor
  FROM v$recovery_file_dest
UNION ALL
SELECT 'Último redo archivado', NVL(TO_CHAR(MAX(completion_time), 'YYYY-MM-DD HH24:MI'), 'ninguno') FROM v$archived_log
UNION ALL
SELECT 'Copias del control file', TO_CHAR(COUNT(*)) FROM v$controlfile
UNION ALL
SELECT 'Grupos de redo con 1 solo miembro', TO_CHAR(COUNT(*)) FROM v$log WHERE members < 2;
PROMPT
PROMPT == 4. Capacidad: uso frente a límites de la instancia (v$resource_limit) ==
SELECT resource_name, current_utilization AS ahora, max_utilization AS maximo, limit_value AS limite
  FROM v$resource_limit WHERE resource_name IN ('processes', 'sessions', 'transactions');
PROMPT
PROMPT == 5. Errores ORA- en el alert log en las últimas 24 h (v$diag_alert_ext) ==
SELECT TO_CHAR(originating_timestamp, 'MM-DD HH24:MI') AS cuando,
       SUBSTR(REGEXP_SUBSTR(message_text, 'ORA-[0-9]+[^' || CHR(10) || ']*'), 1, 90) AS mensaje
  FROM v$diag_alert_ext
 WHERE originating_timestamp > SYSTIMESTAMP - INTERVAL '1' DAY AND message_text LIKE '%ORA-%'
 ORDER BY originating_timestamp DESC FETCH FIRST 10 ROWS ONLY;
PROMPT
PROMPT == 6. Cambios de log por hora en las últimas 24 h (muchos = redo pequeño o carga alta) ==
SELECT TO_CHAR(first_time, 'MM-DD HH24') || 'h' AS hora, COUNT(*) AS cambios
  FROM v$log_history WHERE first_time > SYSDATE - 1 GROUP BY TO_CHAR(first_time, 'MM-DD HH24') ORDER BY 1;
PROMPT
PROMPT == 7. Copias de seguridad RMAN: las últimas (vacío = NO hay copias: alarma) ==
SELECT TO_CHAR(start_time, 'MM-DD HH24:MI') AS inicio, input_type, status, ROUND(output_bytes / 1048576) AS mb,
       elapsed_seconds AS segundos FROM v$rman_backup_job_details ORDER BY start_time DESC FETCH FIRST 5 ROWS ONLY;
PROMPT
PROMPT == 8. Índices que piden atención (no válidos, invisibles olvidados, o con muchas hojas para sus filas) ==
SELECT owner, problema, COUNT(*) AS indices, MIN(index_name) AS ejemplo FROM (
  SELECT owner, index_name,
         CASE WHEN status NOT IN ('VALID', 'N/A') THEN 'NO VÁLIDO (' || status || '): rebuild'
              WHEN visibility = 'INVISIBLE' THEN 'INVISIBLE: ¿olvidado?'
              WHEN last_analyzed IS NULL THEN 'sin estadísticas'
              ELSE 'altura ' || (blevel + 1) || ' con menos de 1 M de filas' END AS problema
    FROM cdb_indexes
   WHERE con_id = 3 AND owner IN ('TIENDASUR', 'ADMIN_ACADEMIA', 'ADMIN_CLINICA', 'ADMIN_RETAIL', 'ADMIN_LOGISTICA', 'ADMIN_FINTECH')
     AND (status NOT IN ('VALID', 'N/A') OR visibility = 'INVISIBLE' OR last_analyzed IS NULL OR (blevel >= 3 AND num_rows < 1000000)))
 GROUP BY owner, problema ORDER BY owner, problema;
PROMPT ("sin estadísticas" en esquemas vacíos es esperable; en uno con datos, el optimizador trabaja a ciegas: DBMS_STATS)
PROMPT
PROMPT == 9. Undo: errores de "snapshot too old" (ORA-01555) o falta de espacio en las últimas 24 h (0 y 0 = bien) ==
SELECT NVL(SUM(ssolderrcnt), 0) AS ora_01555, NVL(SUM(nospaceerrcnt), 0) AS sin_espacio_undo, MAX(maxquerylen) AS consulta_mas_larga_s
  FROM v$undostat WHERE begin_time > SYSDATE - 1;
SPOOL OFF
