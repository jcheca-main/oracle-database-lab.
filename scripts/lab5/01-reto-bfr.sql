-- scripts/lab5/01-reto-bfr.sql
-- Reto profesional de la Parte B: cuantas filas caben de verdad en cada bloque de PEDIDO.
-- Usa DBMS_ROWID.ROWID_BLOCK_NUMBER para agrupar por bloque fisico y compara con NUM_ROWS/BLOCKS.
WHENEVER SQLERROR EXIT FAILURE
ALTER SESSION SET CONTAINER = FREEPDB1;
SET HEADING ON FEEDBACK ON PAGESIZE 100 LINESIZE 120
PROMPT === 1. Filas por bloque fisico de PEDIDO (min, media, max) ===
SELECT COUNT(*) AS bloques_reales, MIN(c) AS min_filas, ROUND(AVG(c),1) AS avg_filas, MAX(c) AS max_filas
  FROM (SELECT blk, COUNT(*) AS c
          FROM (SELECT DBMS_ROWID.ROWID_BLOCK_NUMBER(ROWID) AS blk FROM tiendasur.pedido)
         GROUP BY blk);
PROMPT === 2. Comparacion con el bfr teorico NUM_ROWS / BLOCKS ===
SELECT num_rows, blocks, ROUND(num_rows/blocks,1) AS bfr_teorico
  FROM dba_tables WHERE owner='TIENDASUR' AND table_name='PEDIDO';
EXIT
