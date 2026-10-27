-- scripts/lab5/01-perfil-tiendasur.sql — el perfil del banco: lo que el optimizador sabe de cada tabla y columna (Unidad 3, 3.1.7 y 3.3)
-- Se ejecuta como SYSDBA: bash scripts/ops/sysdba.sh <este archivo> <evidencia>
WHENEVER SQLERROR EXIT FAILURE
SET LINESIZE 170 PAGESIZE 100 FEEDBACK OFF VERIFY OFF TAB OFF
COLUMN table_name FORMAT A8
COLUMN column_name FORMAT A14
COLUMN histogram FORMAT A10
COLUMN data_type FORMAT A12
ALTER SESSION SET CONTAINER = FREEPDB1;
PROMPT
PROMPT ===== 1. Tablas: r filas, b bloques, R bytes por fila y bfr = r / b (compáralo con la ficha de la actividad 3.2) =====
SELECT table_name, num_rows AS r, blocks AS b, avg_row_len AS r_bytes, ROUND(num_rows / blocks) AS bfr,
       ROUND(blocks * 8192 / 1048576, 1) AS mb, last_analyzed
  FROM dba_tables WHERE owner = 'TIENDASUR' ORDER BY table_name;
PROMPT (Actividad 3.2: cliente 1 000 000 filas, bfr 40; pedido 20 000 000, bfr 50. Aquí: 1/10 y 1/20 de las filas, y filas más cortas: bfr mayor)
PROMPT
PROMPT ===== 2. Columnas: valores distintos (NDV), selectividad de una igualdad (1/NDV) y si hay histograma =====
SELECT c.table_name, c.column_name, t.data_type, c.num_distinct AS ndv, ROUND(100 / NULLIF(c.num_distinct, 0), 4) AS pct_por_valor,
       c.num_nulls, c.histogram, c.avg_col_len
  FROM dba_tab_col_statistics c JOIN dba_tab_columns t
    ON t.owner = c.owner AND t.table_name = c.table_name AND t.column_name = c.column_name
 WHERE c.owner = 'TIENDASUR' ORDER BY c.table_name, t.column_id;
PROMPT (Con histograma (FREQUENCY) el optimizador sabe que 'P' es el 2 % y 'C' el 90 %. Sin él, supondría 1/4 = 25 % para cada estado)
PROMPT
PROMPT ===== 3. Los sesgos que dan juego a las consultas Q1-Q16 =====
SELECT 'cliente pais = ES' AS dato, ROUND(100 * AVG(CASE WHEN pais = 'ES' THEN 1 ELSE 0 END), 1) AS pct FROM tiendasur.cliente
UNION ALL SELECT 'cliente ciudad = Lorca', ROUND(100 * AVG(CASE WHEN ciudad = 'Lorca' THEN 1 ELSE 0 END), 2) FROM tiendasur.cliente
UNION ALL SELECT 'cliente apellidos LIKE Gonz%', ROUND(100 * AVG(CASE WHEN apellidos LIKE 'Gonz%' THEN 1 ELSE 0 END), 1) FROM tiendasur.cliente
UNION ALL SELECT 'pedido estado = P', ROUND(100 * AVG(CASE WHEN estado = 'P' THEN 1 ELSE 0 END), 1) FROM tiendasur.pedido
UNION ALL SELECT 'pedido último año', ROUND(100 * AVG(CASE WHEN fecha_pedido >= SYSDATE - 365 THEN 1 ELSE 0 END), 1) FROM tiendasur.pedido;
PROMPT
PROMPT ===== 4. El entorno de medida que usaremos en todo el laboratorio =====
PROMPT   SELECT /*+ GATHER_PLAN_STATISTICS */ ...;                     -- ejecuta y anota filas y lecturas REALES de cada paso
PROMPT   SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(FORMAT => 'IOSTATS LAST'));
PROMPT   E-Rows = filas que el optimizador ESPERABA · A-Rows = filas REALES · Buffers = lecturas lógicas · Reads = físicas
PROMPT   Y en una línea: EXEC lab_tools.medir.consulta('etiqueta', 'SELECT ...')  (01-herramienta-medir.sql)
PROMPT   Regla profesional: se compara con números (Buffers), no con la sensación de "va rápido".
EXIT
