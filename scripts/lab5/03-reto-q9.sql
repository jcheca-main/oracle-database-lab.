-- scripts/lab5/03-reto-q9.sql
-- Reto profesional de la Parte D: Q9 (20 pedidos mas recientes con TODAS sus columnas) usa IX_PED_FECHA.
-- Se mide la version actual y se decide si merece un indice cubriente, razonando con el tamanio de la seccion 8.
WHENEVER SQLERROR EXIT FAILURE
ALTER SESSION SET CONTAINER = FREEPDB1;
SET SERVEROUTPUT ON FORMAT WRAPPED LINESIZE 200
PROMPT === Q9: 20 pedidos mas recientes con todas sus columnas (IX_PED_FECHA, toca la tabla) ===
EXEC lab_tools.medir.consulta('Q9 20 recientes (IX_PED_FECHA)', 'SELECT * FROM tiendasur.pedido ORDER BY fecha_pedido DESC FETCH FIRST 20 ROWS ONLY')
PROMPT === tamanio de referencia (seccion 8) ===
SELECT 'tabla pedido' AS objeto, ROUND(SUM(bytes)/1048576,1) AS mb FROM dba_segments WHERE owner='TIENDASUR' AND segment_name='PEDIDO'
UNION ALL
SELECT 'indice IX_PED_FECHA', ROUND(SUM(bytes)/1048576,1) FROM dba_segments WHERE owner='TIENDASUR' AND segment_name='IX_PED_FECHA';
EXIT
