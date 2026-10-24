-- scripts/lab4/08-reto-literales.sql — RETO de la Parte G: localizar las sentencias que la
-- aplicación repite con literales (una firma force_matching con decenas de cursores casi idénticos).
-- Se ejecuta como C##OPS_RO (solo lectura): es la consulta del primer día de "la CPU está al 100%".
@scripts/ops/marca
SPOOL docs/bitacora/lab4/evidencia/spool/&marca._08-reto-literales.spool.log
SET SQLFORMAT DEFAULT
SET LINESIZE 210 PAGESIZE 60 FEEDBACK OFF
COLUMN firma FORMAT A32
COLUMN ejemplo FORMAT A62
PROMPT == Sentencias con más de 50 cursores distintos que comparten la misma forma (force_matching_signature) ==
SELECT force_matching_signature AS firma,
       COUNT(*) AS cursores_distintos,
       SUM(executions) AS ejecuciones_totales,
       ROUND(SUM(sharable_mem) / 1024) AS kb_shared_pool,
       MIN(SUBSTR(sql_text, 1, 62)) AS ejemplo
  FROM v$sql
 WHERE force_matching_signature <> 0
 GROUP BY force_matching_signature
HAVING COUNT(*) > 50
 ORDER BY cursores_distintos DESC;
PROMPT (Firma 0 es "sin firma": cada sentencia, una forma. Los literales quedan ocultos tras la misma firma)
SPOOL OFF
EXIT
