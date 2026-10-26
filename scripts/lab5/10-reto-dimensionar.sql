-- scripts/lab5/10-reto-dimensionar.sql
-- Reto profesional de la Parte K: dimensionar el redo. Cuenta cambios de log por hora
-- (v$log_history) y estima el redo generado por hora para proponer un tamaño de grupo
-- que aguante como mucho 4 cambios/hora en el pico.
WHENEVER SQLERROR EXIT FAILURE
SET LINESIZE 160 PAGESIZE 100 FEEDBACK OFF
COLUMN hora FORMAT A6
PROMPT ==== cambios de log por hora (v$log_history) ====
SELECT TO_CHAR(first_time, 'HH24') AS hora, COUNT(*) AS cambios
FROM v$log_history GROUP BY TO_CHAR(first_time, 'HH24') ORDER BY 1;
PROMPT ==== tamano actual de grupo y total de redo por hilo ====
SELECT COUNT(*) AS grupos, ROUND(SUM(bytes)/1048576) AS mb_por_grupo FROM v$log;
PROMPT ==== redo generado por hora (v$sysstat, en bloques de 512 B) ====
SELECT TO_CHAR(sample_time,'HH24') AS hora, COUNT(*) FROM v$active_session_history
WHERE event LIKE 'log file switch%' GROUP BY TO_CHAR(sample_time,'HH24') ORDER BY 1;
PROMPT ==== ultimo cambio de log y su hora ====
SELECT sequence#, TO_CHAR(first_time,'YYYY-MM-DD HH24:MI:SS') AS inicio FROM v$log_history ORDER BY sequence# DESC FETCH FIRST 3 ROWS ONLY;
EXIT
