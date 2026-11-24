-- scripts/lab6/07-memoria.sql — leer la memoria en vivo, sin convertirla en la explicación de todo (Unidad 5, 5.7.2)
-- Solo lectura:  bash scripts/ops/ro.sh scripts/lab6/07-memoria.sql
@scripts/ops/marca
@scripts/ops/cabecera 07-memoria
SPOOL docs/bitacora/lab6/evidencia/spool/&marca._07-memoria.spool.log
PROMPT &cab1
PROMPT &cab2
SET TERMOUT OFF
SET SQLFORMAT DEFAULT
SET TERMOUT ON
SET LINESIZE 150 PAGESIZE 100 FEEDBACK OFF
COLUMN name FORMAT A34
COLUMN component FORMAT A22
COLUMN last_oper_type FORMAT A13
COLUMN pname FORMAT A6
PROMPT == 1. La SGA por componentes (V$SGAINFO) ==
SELECT name, ROUND(bytes / 1048576) AS mb, resizeable FROM v$sgainfo ORDER BY bytes DESC;
PROMPT == 2. Componentes dinámicos: entre qué tamaños se han movido desde el arranque (ASMM) ==
SELECT component, ROUND(current_size / 1048576) AS actual_mb, ROUND(min_size / 1048576) AS min_mb,
       ROUND(max_size / 1048576) AS max_mb, ROUND(user_specified_size / 1048576) AS fijado_mb, last_oper_type
  FROM v$sga_dynamic_components WHERE current_size > 0 ORDER BY current_size DESC;
SELECT COUNT(*) AS movimientos_grow_shrink FROM v$memory_resize_ops WHERE oper_type IN ('GROW', 'SHRINK');
PROMPT == 3. La PGA de la instancia (V$PGASTAT) ==
SELECT name, CASE WHEN unit = 'bytes' THEN ROUND(value / 1048576) ELSE value END AS valor,
       CASE WHEN unit = 'bytes' THEN 'MB' ELSE unit END AS unidad
  FROM v$pgastat WHERE name IN ('aggregate PGA target parameter', 'aggregate PGA auto target', 'total PGA inuse',
                                'total PGA allocated', 'maximum PGA allocated', 'cache hit percentage', 'over allocation count')
   AND con_id = 0;
PROMPT == 4. Qué procesos consumen más PGA ahora ==
SELECT pname, spid, ROUND(pga_alloc_mem / 1048576, 1) AS pga_mb FROM v$process ORDER BY pga_alloc_mem DESC FETCH FIRST 5 ROWS ONLY;
PROMPT == 5. Antes de cambiar la memoria, pregunta a los advisors (factor 1 = tamaño actual) ==
SELECT sga_size AS sga_mb, sga_size_factor AS factor, estd_db_time_factor, estd_physical_reads FROM v$sga_target_advice ORDER BY sga_size;
SELECT ROUND(pga_target_for_estimate / 1048576) AS pga_mb, pga_target_factor AS factor, estd_pga_cache_hit_percentage AS hit_pct,
       estd_overalloc_count AS overalloc FROM v$pga_target_advice WHERE pga_target_factor IN (0.25, 0.5, 0.75, 1, 2) ORDER BY 1;
SPOOL OFF
