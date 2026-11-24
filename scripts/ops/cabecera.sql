-- scripts/ops/cabecera.sql — la cabecera de evidencia del Lab 6 dentro de un SPOOL de SQLcl
-- Se llama ANTES del SPOOL (solo calcula, sin escribir nada) y, ya dentro del SPOOL, se imprimen &cab1 y &cab2:
--   @scripts/ops/cabecera <origen>
--   SPOOL ...
--   PROMPT &cab1
--   PROMPT &cab2
-- &ESTUDIANTE lo definen ro.sh (desde config/.env) y login.sql (scripts/ops/alumno.sh).
SET TERMOUT OFF
COLUMN cab1 NEW_VALUE cab1 NOPRINT
COLUMN cab2 NEW_VALUE cab2 NOPRINT
SELECT '== EVIDENCIA alumno=&ESTUDIANTE hora=' || TO_CHAR(SYS_EXTRACT_UTC(SYSTIMESTAMP), 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
       || ' origen=&1' AS cab1,
       '== EVIDENCIA contenedor=' || i.host_name || ' dbid=' || d.dbid || ' arranque='
       || TO_CHAR(i.startup_time, 'YYYY-MM-DD"T"HH24:MI:SS') || ' scn=' || d.current_scn AS cab2
  FROM v$instance i, v$database d;
SET TERMOUT ON
