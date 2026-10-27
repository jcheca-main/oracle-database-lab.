-- scripts/lab5/11-reto-fra-llena.sql
-- Reto profesional Parte L: provocar de verdad la FRA llena con redo real (no con un
-- UPDATE sin cambio) y documentar la cadena ORA-19815 -> ORA-19809/ORA-16038 -> grupos
-- sin archivar -> sesiones esperando, y su remedio.
WHENEVER SQLERROR CONTINUE
SET LINESIZE 160 PAGESIZE 100 FEEDBACK OFF
PROMPT ==== 1. FRA antes ====
SELECT ROUND(space_limit/1048576) AS limite_mb, ROUND(space_used/1048576,1) AS usado_mb FROM v$recovery_file_dest;
PROMPT ==== 2. Encoger la FRA a 2M (solo laboratorio) ====
ALTER SYSTEM SET db_recovery_file_dest_size = 2M SCOPE = MEMORY;
PROMPT ==== 3. UPDATE real de 300000 filas (genera ~100MB de redo) ====
ALTER SESSION SET CONTAINER = FREEPDB1;
UPDATE tiendasur.pedido SET importe = importe + 1 WHERE id_pedido <= 300000;
COMMIT;
ALTER SESSION SET CONTAINER = CDB$ROOT;
PROMPT ==== 4. Pedir archivar el grupo lleno -> debe fallar (FRA 2M) ====
ALTER SYSTEM ARCHIVE LOG CURRENT;
PROMPT ==== 5. Sintoma: grupos con ARC=NO y eventos de espera ====
SELECT group#, sequence#, archived, status FROM v$log ORDER BY group#;
SELECT event, COUNT(*) FROM v$session WHERE wait_class <> 'Idle' GROUP BY event ORDER BY 2 DESC FETCH FIRST 5 ROWS ONLY;
PROMPT ==== 6. Alert log: ORA-19815 / ORA-19809 / ORA-16038 ====
SELECT TO_CHAR(originating_timestamp,'HH24:MI:SS') AS hora,
       SUBSTR(REGEXP_SUBSTR(message_text, 'ORA-[0-9]+[^'||CHR(10)||']*'),1,110) AS msg
FROM v$diag_alert_ext
WHERE originating_timestamp > SYSTIMESTAMP - INTERVAL '5' MINUTE
AND (message_text LIKE '%ORA-19809%' OR message_text LIKE '%ORA-19815%' OR message_text LIKE '%ORA-16038%' OR message_text LIKE '%ORA-00257%')
ORDER BY originating_timestamp FETCH FIRST 8 ROWS ONLY;
PROMPT ==== 7. Remedio: devolver espacio; ARCn reintenta solo ====
ALTER SYSTEM SET db_recovery_file_dest_size = 4G SCOPE = MEMORY;
ALTER SYSTEM ARCHIVE LOG CURRENT;
SELECT group#, sequence#, archived, status FROM v$log ORDER BY group#;
SELECT ROUND(space_limit/1048576) AS limite_mb, ROUND(space_used/1048576,1) AS usado_mb FROM v$recovery_file_dest;
EXIT
