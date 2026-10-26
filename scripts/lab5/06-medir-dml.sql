-- scripts/lab5/06-medir-dml.sql — lo que cuesta escribir en PEDIDO con los índices que tenga AHORA (Q16 de la Actividad 3.2)
-- No se lanza solo: 06-indices.sh le antepone DEFINE escenario = '...' y lo ejecuta en cada escenario. Todo se deshace (ROLLBACK).
-- 2000 operaciones de una fila, como llegan en OLTP (TiendaSur: 300 INSERT/s y 150 UPDATE de estado/s).
WHENEVER SQLERROR EXIT FAILURE
SET LINESIZE 200 PAGESIZE 100 FEEDBACK OFF VERIFY OFF TAB OFF
COLUMN indices FORMAT A110 WORD_WRAPPED
ALTER SESSION SET CONTAINER = FREEPDB1;
SET SERVEROUTPUT ON FORMAT WRAPPED
PROMPT
PROMPT ===== Escenario: &escenario =====
SELECT COUNT(*) AS indices_en_pedido, LISTAGG(index_name, ', ') WITHIN GROUP (ORDER BY index_name) AS indices
  FROM dba_indexes WHERE owner = 'TIENDASUR' AND table_name = 'PEDIDO';
EXEC lab_tools.medir.dml('&escenario: 2000 INSERT', q'[BEGIN FOR i IN 1 .. 2000 LOOP INSERT INTO tiendasur.pedido (id_pedido, id_cliente, fecha_pedido, estado, importe, canal, codigo_postal) VALUES (2000000 + i, MOD(i * 7919, 100000) + 1, SYSTIMESTAMP, 'P', 10 + MOD(i, 90), 'W', TO_CHAR(25000 + MOD(i * 31, 11000))); END LOOP; END;]', 2000)
EXEC lab_tools.medir.dml('&escenario: 2000 UPDATE estado', q'[BEGIN FOR i IN 980001 .. 982000 LOOP UPDATE tiendasur.pedido SET estado = 'E' WHERE id_pedido = i; END LOOP; END;]', 2000)
EXEC lab_tools.medir.dml('&escenario: 2000 UPDATE importe', q'[BEGIN FOR i IN 980001 .. 982000 LOOP UPDATE tiendasur.pedido SET importe = importe + 1 WHERE id_pedido = i; END LOOP; END;]', 2000)
EXEC lab_tools.medir.dml('&escenario: 2000 DELETE', q'[BEGIN FOR i IN 1 .. 2000 LOOP DELETE FROM tiendasur.pedido WHERE id_pedido = i; END LOOP; END;]', 2000)
EXIT
