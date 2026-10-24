-- scripts/lab4/13-reto-matriculas.sql — reto Parte L: dimensionar ACA_MATRICULAS (predicción vs realidad)
-- Se ejecuta como SYSDBA: bash scripts/ops/sysdba.sh <este archivo> <evidencia>
-- La predicción se hizo ANTES de mirar las estadísticas, a partir del DDL (R ≈ 35 bytes/fila).
WHENEVER SQLERROR EXIT FAILURE
SET LINESIZE 170 PAGESIZE 100 FEEDBACK OFF
PROMPT ===== RETO L - ACA_MATRICULAS: predicción vs realidad =====
PROMPT Predicción (hecha antes de mirar, a partir del DDL): R ≈ 35 bytes/fila
PROMPT   bfr (Unidad 3) = floor((8192-96)*0.9/35) = floor(7286.4/35) = 208 filas/bloque
PROMPT   b = ceil(60000/208) = 289 bloques (~2,3 MB)
PROMPT   bfr (Oracle)   = floor((8192-122)*0.9/(35+2)) = floor(7263/37) = 196 filas/bloque
PROMPT   b = ceil(60000/196) = 307 bloques (~2,4 MB)
PROMPT
PROMPT ----- Ahora, lo que dicen las estadísticas y el segmento -----
ALTER SESSION SET CONTAINER = FREEPDB1;
COLUMN tablespace_name FORMAT A14
EXEC DBMS_STATS.GATHER_TABLE_STATS('ADMIN_ACADEMIA', 'ACA_MATRICULAS')
SELECT t.num_rows AS r, t.avg_row_len AS r_bytes, t.blocks AS bloques_hwm, t.pct_free,
       s.blocks AS bloques_asignados, ROUND(s.bytes/1048576,2) AS mb
  FROM dba_tables t JOIN dba_segments s ON s.owner = t.owner AND s.segment_name = t.table_name
 WHERE t.owner = 'ADMIN_ACADEMIA' AND t.table_name = 'ACA_MATRICULAS';
PROMPT -- bfr MEDIDO: filas reales por bloque
SELECT COUNT(*) AS bloques_con_filas, MIN(n) AS min_filas, ROUND(AVG(n),1) AS media, MAX(n) AS max_filas
  FROM (SELECT DBMS_ROWID.ROWID_BLOCK_NUMBER(ROWID,'BIGFILE') AS blk, COUNT(*) AS n
          FROM admin_academia.aca_matriculas GROUP BY DBMS_ROWID.ROWID_BLOCK_NUMBER(ROWID,'BIGFILE'));
PROMPT -- Coste de un recorrido completo en HDD (150 MiB/s): ms = bloques x 8192 / 157286,4
SELECT blocks, ROUND(blocks * 8192 / 157286.4, 1) AS t_hdd_ms
  FROM dba_tables WHERE owner = 'ADMIN_ACADEMIA' AND table_name = 'ACA_MATRICULAS';
EXIT
