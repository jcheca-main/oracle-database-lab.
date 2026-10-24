-- scripts/lab4/08-memoria.sql — SGA y PGA por dentro (SQLcl · C##OPS_RO · servicio FREE)
@scripts/ops/marca
SPOOL docs/bitacora/lab4/evidencia/spool/&marca._08-memoria.spool.log
SET SQLFORMAT DEFAULT
SET LINESIZE 180 PAGESIZE 100 FEEDBACK OFF
COLUMN name FORMAT A36
COLUMN component FORMAT A30
COLUMN pname FORMAT A8
COLUMN unidad FORMAT A8
COLUMN display_value FORMAT A12
PROMPT
PROMPT == 1. Modelo de gestión de memoria: ¿quién reparte? ==
SELECT name, display_value FROM v$parameter
 WHERE name IN ('memory_size', 'memory_target', 'sga_target', 'sga_max_size',
                'pga_aggregate_target', 'pga_aggregate_limit', 'db_cache_size', 'shared_pool_size')
 ORDER BY name;
PROMPT
PROMPT == 2. La SGA: el resumen que imprime STARTUP (v$sga) ==
SELECT name, ROUND(value / 1048576, 1) AS mb FROM v$sga;
PROMPT
PROMPT == 3. Componentes de la SGA y si se pueden redimensionar (v$sgainfo) ==
SELECT name, ROUND(bytes / 1048576, 1) AS mb, resizeable FROM v$sgainfo ORDER BY bytes DESC;
PROMPT
PROMPT == 4. Reparto dinámico con ASMM: tamaño actual y operaciones de ajuste (v$sga_dynamic_components) ==
SELECT component, ROUND(current_size / 1048576) AS actual_mb, ROUND(min_size / 1048576) AS min_mb,
       ROUND(user_specified_size / 1048576) AS fijado_mb, oper_count AS ajustes
  FROM v$sga_dynamic_components WHERE current_size > 0 ORDER BY current_size DESC;
PROMPT
PROMPT == 5. Asesor: ¿qué pasaría con otra SGA_TARGET? (factor 1 = tamaño actual) ==
SELECT sga_size AS sga_mb, sga_size_factor AS factor, estd_db_time_factor AS tiempo_bd_estimado, estd_physical_reads AS lecturas_fisicas_est
  FROM v$sga_target_advice ORDER BY sga_size;
PROMPT
PROMPT == 6. La PGA: memoria privada de cada proceso (v$pgastat) ==
SELECT name, ROUND(CASE unit WHEN 'bytes' THEN value / 1048576 ELSE value END, 1) AS valor,
       CASE unit WHEN 'bytes' THEN 'MB' ELSE unit END AS unidad
  FROM v$pgastat
 WHERE name IN ('aggregate PGA target parameter', 'aggregate PGA auto target', 'total PGA inuse',
                'total PGA allocated', 'maximum PGA allocated', 'over allocation count',
                'cache hit percentage')
   AND con_id = 0;   -- con_id 0 = toda la instancia
PROMPT
PROMPT == 7. Los procesos que más PGA usan ahora mismo (v$process) ==
SELECT * FROM (
  SELECT NVL(pname, 'servidor') AS pname, spid, ROUND(pga_used_mem / 1048576, 1) AS usada_mb,
         ROUND(pga_alloc_mem / 1048576, 1) AS asignada_mb, ROUND(pga_max_mem / 1048576, 1) AS maxima_mb
    FROM v$process ORDER BY pga_alloc_mem DESC)
 WHERE ROWNUM <= 8;
SPOOL OFF
