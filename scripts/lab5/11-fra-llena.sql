-- scripts/lab5/11-fra-llena.sql — escenario de examen: la FRA se llena y el archivador se detiene
-- Se ejecuta como SYSDBA: bash scripts/ops/sysdba.sh <este archivo> <evidencia>
-- Se provoca de forma CONTROLADA (un solo cambio de log) y se resuelve al final del propio script.
WHENEVER SQLERROR CONTINUE
SET LINESIZE 160 PAGESIZE 100 FEEDBACK OFF
COLUMN name FORMAT A30
COLUMN message_text FORMAT A100
PROMPT
PROMPT ===== 1. Espacio de la FRA ahora =====
SELECT name, ROUND(space_limit / 1048576) AS limite_mb, ROUND(space_used / 1048576, 1) AS usado_mb FROM v$recovery_file_dest;
PROMPT
PROMPT ===== 2. Encoger la FRA por debajo de lo necesario (solo laboratorio) =====
ALTER SYSTEM SET db_recovery_file_dest_size = 2M SCOPE = MEMORY;
PROMPT
PROMPT ===== 3. Generar redo (UPDATE sin cambio real de 20 000 filas) y pedir que se archive =====
ALTER SESSION SET CONTAINER = FREEPDB1;
UPDATE admin_academia.aca_estudiantes SET estado = estado;
COMMIT;
ALTER SESSION SET CONTAINER = CDB$ROOT;
ALTER SYSTEM ARCHIVE LOG CURRENT;
PROMPT
PROMPT ===== 4. Lo que verá el DBA de guardia: grupos sin archivar y el alert log =====
SELECT group#, sequence#, archived, status FROM v$log ORDER BY group#;
SELECT TO_CHAR(originating_timestamp, 'HH24:MI:SS') AS hora, SUBSTR(REGEXP_SUBSTR(message_text, 'ORA-[0-9]+[^' || CHR(10) || ']*'), 1, 100) AS message_text
  FROM v$diag_alert_ext
 WHERE originating_timestamp > SYSTIMESTAMP - INTERVAL '5' MINUTE
   AND (message_text LIKE '%ORA-19809%' OR message_text LIKE '%ORA-19815%' OR message_text LIKE '%ORA-16038%' OR message_text LIKE '%ORA-00257%')
 ORDER BY originating_timestamp FETCH FIRST 6 ROWS ONLY;
PROMPT
PROMPT ===== 5. Solución inmediata: devolver espacio a la FRA. ARCn reintenta solo =====
ALTER SYSTEM SET db_recovery_file_dest_size = 4G SCOPE = MEMORY;
ALTER SYSTEM ARCHIVE LOG CURRENT;
SELECT group#, sequence#, archived, status FROM v$log ORDER BY group#;
SELECT name, ROUND(space_limit / 1048576) AS limite_mb, ROUND(space_used / 1048576, 1) AS usado_mb FROM v$recovery_file_dest;
EXIT
