-- scripts/lab5/04-agrupamiento-equilibrio.sql — factor de agrupamiento (clustering factor) y punto de equilibrio índice / recorrido completo
-- Se ejecuta como SYSDBA: bash scripts/ops/sysdba.sh <este archivo> <evidencia>
-- Solo lee. Mide, para cada porcentaje de filas, cuánto cuesta ir por índice (con agrupamiento bueno y malo) y cuánto la tabla entera.
WHENEVER SQLERROR EXIT FAILURE
SET LINESIZE 170 PAGESIZE 100 FEEDBACK OFF VERIFY OFF TAB OFF
COLUMN index_name FORMAT A16
COLUMN veredicto FORMAT A52
ALTER SESSION SET CONTAINER = FREEPDB1;
SET SERVEROUTPUT ON FORMAT WRAPPED
PROMPT
PROMPT ===== 1. El factor de agrupamiento (CF) según el diccionario: ¿cerca de los BLOQUES de la tabla o cerca de las FILAS? =====
SELECT i.index_name, i.clustering_factor AS cf, t.blocks AS bloques_tabla, t.num_rows AS filas_tabla,
       CASE WHEN i.clustering_factor < 2 * t.blocks THEN 'BUENO: filas vecinas en el índice, vecinas en disco'
            WHEN i.clustering_factor > 0.5 * t.num_rows THEN 'MALO: casi cada entrada salta a otro bloque'
            ELSE 'intermedio' END AS veredicto
  FROM dba_indexes i JOIN dba_tables t ON t.owner = i.table_owner AND t.table_name = i.table_name
 WHERE i.owner = 'TIENDASUR' AND i.table_name = 'PEDIDO' ORDER BY i.clustering_factor;
PROMPT
PROMPT ===== 2. Calcularlo a mano: recorrer el índice en orden y contar cuántas veces cambia el bloque de la tabla =====
SELECT 'IX_PED_FECHA' AS index_name, SUM(cambia) AS cf_calculado FROM (
  SELECT CASE WHEN DBMS_ROWID.ROWID_BLOCK_NUMBER(ROWID, 'BIGFILE')
                   = LAG(DBMS_ROWID.ROWID_BLOCK_NUMBER(ROWID, 'BIGFILE')) OVER (ORDER BY fecha_pedido, ROWID) THEN 0 ELSE 1 END AS cambia
    FROM tiendasur.pedido)
UNION ALL
SELECT 'IX_PED_CLIENTE', SUM(cambia) FROM (
  SELECT CASE WHEN DBMS_ROWID.ROWID_BLOCK_NUMBER(ROWID, 'BIGFILE')
                   = LAG(DBMS_ROWID.ROWID_BLOCK_NUMBER(ROWID, 'BIGFILE')) OVER (ORDER BY id_cliente, ROWID) THEN 0 ELSE 1 END AS cambia
    FROM tiendasur.pedido);
PROMPT (Coincide con DBA_INDEXES: el CF es exactamente "cuántos bloques distintos leería si recorriera el índice entero")
PROMPT
PROMPT ===== 3. La curva del punto de equilibrio, MEDIDA: lecturas lógicas para sumar el importe del k % de los pedidos =====
DECLARE
  b NUMBER; r NUMBER; v NUMBER; lr NUMBER; ini DATE; idx_bueno NUMBER; idx_malo NUMBER; completo NUMBER; elige VARCHAR2(30);
  FUNCTION estad(p VARCHAR2) RETURN NUMBER IS x NUMBER;
  BEGIN SELECT m.value INTO x FROM v$mystat m JOIN v$statname s ON s.statistic# = m.statistic# WHERE s.name = p; RETURN x; END;
  FUNCTION lecturas(q VARCHAR2) RETURN NUMBER IS x NUMBER;
  BEGIN
    EXECUTE IMMEDIATE q INTO v;                               -- calentamiento
    x := estad('session logical reads'); EXECUTE IMMEDIATE q INTO v; RETURN estad('session logical reads') - x;
  END;
  FUNCTION optimizador(q VARCHAR2) RETURN VARCHAR2 IS x VARCHAR2(30);
  BEGIN
    DELETE FROM plan_table WHERE statement_id = 'lab5';
    EXECUTE IMMEDIATE 'EXPLAIN PLAN SET STATEMENT_ID = ''lab5'' FOR ' || q;
    SELECT MAX(CASE WHEN operation = 'TABLE ACCESS' AND options = 'FULL' THEN 'recorrido completo'
                    WHEN operation = 'INDEX' THEN 'índice' END) INTO x FROM plan_table WHERE statement_id = 'lab5';
    RETURN x;
  END;
BEGIN
  SELECT blocks, num_rows INTO b, r FROM dba_tables WHERE owner = 'TIENDASUR' AND table_name = 'PEDIDO';
  SELECT MIN(fecha_pedido) INTO ini FROM tiendasur.pedido;
  DBMS_OUTPUT.PUT_LINE('b = ' || b || ' bloques, r = ' || r || ' filas, bfr = ' || ROUND(r / b));
  DBMS_OUTPUT.PUT_LINE(RPAD('k %', 8) || LPAD('filas', 9) || LPAD('índice CF bueno', 18) || LPAD('índice CF malo', 17)
       || LPAD('tabla entera', 15) || '   el optimizador elige (CF malo)');
  completo := lecturas('SELECT /*+ FULL(p) */ SUM(importe) FROM tiendasur.pedido p');
  FOR f IN (SELECT COLUMN_VALUE AS pct FROM TABLE(sys.odcinumberlist(0.01, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100))) LOOP
    idx_bueno := lecturas('SELECT /*+ INDEX(p ix_ped_fecha) */ SUM(importe) FROM tiendasur.pedido p WHERE fecha_pedido < TIMESTAMP '''
                          || TO_CHAR(ini + 3 * 365 * f.pct / 100, 'YYYY-MM-DD HH24:MI:SS') || '''');
    idx_malo  := lecturas('SELECT /*+ INDEX(p ix_ped_cliente) */ SUM(importe) FROM tiendasur.pedido p WHERE id_cliente <= ' || ROUND(1000 * f.pct));
    elige     := optimizador('SELECT SUM(importe) FROM tiendasur.pedido p WHERE id_cliente <= ' || ROUND(1000 * f.pct));
    DBMS_OUTPUT.PUT_LINE(RPAD(f.pct || ' %', 8) || LPAD(ROUND(r * f.pct / 100), 9) || LPAD(idx_bueno, 18) || LPAD(idx_malo, 17)
         || LPAD(completo, 15) || '   ' || elige || CASE WHEN idx_bueno > completo THEN '   <- hasta el índice bueno pierde' WHEN idx_malo > completo THEN '   <- el índice malo ya lee más que la tabla' END);
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('');
  DBMS_OUTPUT.PUT_LINE('Teoría (Unidad 3, 3.1.8): con CF malo, cada fila es una lectura aleatoria -> el índice compensa si k/r < (1/bfr)·(c_sec/c_aleat)');
  DBMS_OUTPUT.PUT_LINE('  En lecturas lógicas (c_sec = c_aleat):  k/r < 1/' || ROUND(r / b) || ' = ' || ROUND(100 * b / r, 2) || ' %');
  DBMS_OUTPUT.PUT_LINE('  En disco, con c_sec/c_aleat = 1/5:      k/r < ' || ROUND(100 * b / r / 5, 2) || ' %   (la lectura aleatoria es la cara)');
  ROLLBACK;
END;
/
PROMPT (Con CF BUENO el índice lee unas k/bfr hojas y bloques: compensa hasta porcentajes mucho mayores. El CF es propiedad de la TABLA
PROMPT  (de cómo están ordenadas sus filas), no del índice: reconstruir el índice NO lo mejora; reordenar la tabla, sí)
EXIT
