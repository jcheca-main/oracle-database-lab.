-- scripts/lab6/04-deltas.sql — acumulados frente a deltas: la película, no la foto (Unidad 5, 5.4.8)
-- SYSDBA:  bash scripts/ops/sysdba.sh scripts/lab6/04-deltas.sql "$EVID_LAB6/script/$(ts)_04-deltas.script.log"
-- Mide lo que cuesta una carga conocida (10 recorridos completos de TIENDASUR.PEDIDO) restando dos fotos.
SET LINESIZE 150 PAGESIZE 100 FEEDBACK OFF VERIFY OFF TIMING OFF
ALTER SESSION SET CONTAINER = FREEPDB1;
COLUMN metric_name FORMAT A26
COLUMN stat_name FORMAT A10
COLUMN metric_unit FORMAT A28
COLUMN event FORMAT A34
COLUMN wait_class FORMAT A14
PROMPT == 1. Tasas ya calculadas por MMON para ESTA PDB (V$CON_SYSMETRIC, último minuto) ==
PROMPT (V$SYSMETRIC son las de la instancia: dentro de una PDB sale vacía)
SELECT metric_name, ROUND(value, 2) AS valor, metric_unit FROM v$con_sysmetric
 WHERE metric_name IN ('Average Active Sessions', 'Executions Per Sec', 'User Transaction Per Sec',
                       'Database Time Per Sec', 'CPU Usage Per Sec')
 ORDER BY metric_name;
PROMPT == 2. Acumulados desde el arranque: sin el "desde cuándo" no significan nada ==
SELECT TO_CHAR(startup_time, 'YYYY-MM-DD HH24:MI') AS arranque, ROUND((SYSDATE - startup_time) * 24 * 60) AS minutos_arriba
  FROM v$instance;
SELECT stat_name, ROUND(value / 1e6, 1) AS segundos FROM v$sys_time_model WHERE stat_name IN ('DB time', 'DB CPU');
-- Foto 1 (una sola consulta: guarda cinco valores en variables de sustitución)
COLUMN dbt NEW_VALUE dbt1 NOPRINT
COLUMN cpu NEW_VALUE cpu1 NOPRINT
COLUMN lr  NEW_VALUE lr1  NOPRINT
COLUMN ex  NEW_VALUE ex1  NOPRINT
COLUMN t   NEW_VALUE t1   NOPRINT
SELECT (SELECT value FROM v$sys_time_model WHERE stat_name = 'DB time') AS dbt,
       (SELECT value FROM v$sys_time_model WHERE stat_name = 'DB CPU')  AS cpu,
       (SELECT value FROM v$sysstat WHERE name = 'session logical reads') AS lr,
       (SELECT value FROM v$sysstat WHERE name = 'execute count')        AS ex,
       DBMS_UTILITY.GET_TIME AS t FROM dual;
PROMPT == 3. La carga conocida: 10 recorridos completos de PEDIDO (un millón de filas cada uno) ==
DECLARE n NUMBER;
BEGIN
  FOR i IN 1 .. 10 LOOP
    SELECT /*+ FULL(p) */ COUNT(*) INTO n FROM tiendasur.pedido p WHERE importe > 100;
  END LOOP;
END;
/
-- Foto 2
COLUMN dbt NEW_VALUE dbt2 NOPRINT
COLUMN cpu NEW_VALUE cpu2 NOPRINT
COLUMN lr  NEW_VALUE lr2  NOPRINT
COLUMN ex  NEW_VALUE ex2  NOPRINT
COLUMN t   NEW_VALUE t2   NOPRINT
SELECT (SELECT value FROM v$sys_time_model WHERE stat_name = 'DB time') AS dbt,
       (SELECT value FROM v$sys_time_model WHERE stat_name = 'DB CPU')  AS cpu,
       (SELECT value FROM v$sysstat WHERE name = 'session logical reads') AS lr,
       (SELECT value FROM v$sysstat WHERE name = 'execute count')        AS ex,
       DBMS_UTILITY.GET_TIME AS t FROM dual;
PROMPT == 4. El delta: lo que costó la carga ==
COLUMN magnitud FORMAT A32
SELECT 'Tiempo de reloj (s)' AS magnitud, ROUND((&t2 - &t1) / 100, 2) AS delta FROM dual
UNION ALL SELECT 'DB time (s)', ROUND((&dbt2 - &dbt1) / 1e6, 2) FROM dual
UNION ALL SELECT 'DB CPU (s)', ROUND((&cpu2 - &cpu1) / 1e6, 2) FROM dual
UNION ALL SELECT 'Lecturas lógicas', &lr2 - &lr1 FROM dual
UNION ALL SELECT 'Ejecuciones (incluye recursivas)', &ex2 - &ex1 FROM dual
UNION ALL SELECT 'Lecturas lógicas por recorrido', ROUND((&lr2 - &lr1) / 10) FROM dual;
PROMPT == 5. En qué ESPERA esta PDB desde el arranque (clases que no son Idle, acumulado) ==
SELECT wait_class, ROUND(SUM(time_waited_micro) / 1e6, 1) AS segundos, SUM(total_waits) AS esperas
  FROM v$system_event WHERE wait_class <> 'Idle' GROUP BY wait_class ORDER BY segundos DESC FETCH FIRST 6 ROWS ONLY;
EXIT
