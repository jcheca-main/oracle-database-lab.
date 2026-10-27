-- scripts/lab5/12-undo-y-redo.sql — el undo también genera redo, y cada operación deja un undo de distinto tamaño (Unidad 3, 3.4; Unidad 4, 4.5)
-- Se ejecuta como SYSDBA: bash scripts/ops/sysdba.sh <este archivo> <evidencia>. Todo se deshace con ROLLBACK.
WHENEVER SQLERROR EXIT FAILURE
SET LINESIZE 170 PAGESIZE 100 FEEDBACK OFF VERIFY OFF TAB OFF
ALTER SESSION SET CONTAINER = FREEPDB1;
SET SERVEROUTPUT ON FORMAT WRAPPED
PROMPT
PROMPT ===== 1. INSERT, UPDATE y DELETE de 10 000 pedidos: undo que dejan y redo que generan =====
DECLARE
  rd NUMBER; uv NUMBER; ub NUMBER;
  FUNCTION estad(p VARCHAR2) RETURN NUMBER IS x NUMBER;
  BEGIN SELECT m.value INTO x FROM v$mystat m JOIN v$statname s ON s.statistic# = m.statistic# WHERE s.name = p; RETURN x; END;
  FUNCTION undo_bloques RETURN NUMBER IS x NUMBER;
  BEGIN
    SELECT NVL(SUM(t.used_ublk), 0) INTO x FROM v$transaction t JOIN v$session s ON s.taddr = t.addr
     WHERE s.sid = SYS_CONTEXT('USERENV', 'SID');
    RETURN x;
  END;
  PROCEDURE probar(etiqueta VARCHAR2, sentencia VARCHAR2) IS
  BEGIN
    rd := estad('redo size'); uv := estad('undo change vector size');
    EXECUTE IMMEDIATE sentencia;
    ub := undo_bloques;
    DBMS_OUTPUT.PUT_LINE(RPAD(etiqueta, 22) || ' bloques de undo = ' || LPAD(ub, 5) || ' (' || LPAD(ROUND(ub * 8192 / 1024), 6) || ' KB)'
      || ' | redo total = ' || LPAD(ROUND((estad('redo size') - rd) / 1024), 6) || ' KB'
      || ', del cual describe el undo = ' || LPAD(ROUND((estad('undo change vector size') - uv) / 1024), 6) || ' KB');
    rd := estad('redo size');
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE(RPAD('   y su ROLLBACK', 22) || ' redo generado al deshacer = ' || ROUND((estad('redo size') - rd) / 1024) || ' KB');
  END;
BEGIN
  probar('INSERT 10 000 filas', 'INSERT INTO tiendasur.pedido (id_pedido, id_cliente, fecha_pedido, estado, importe, canal, codigo_postal)
      SELECT 3000000 + LEVEL, MOD(LEVEL, 100000) + 1, SYSTIMESTAMP, ''P'', 10, ''W'', ''30001'' FROM dual CONNECT BY LEVEL <= 10000');
  probar('UPDATE 10 000 filas', 'UPDATE tiendasur.pedido SET canal = ''T'' WHERE id_pedido BETWEEN 100001 AND 110000');
  probar('DELETE 10 000 filas', 'DELETE FROM tiendasur.pedido WHERE id_pedido BETWEEN 100001 AND 110000');
END;
/
PROMPT
PROMPT   INSERT: el undo solo guarda "borra este ROWID" -> poco undo.   DELETE: guarda la fila ENTERA (y sus entradas de índice) -> mucho.
PROMPT   UPDATE: guarda el valor anterior de las columnas cambiadas.     Y TODO cambio en el undo se protege con redo:
PROMPT   si la instancia cae, la recuperación primero rehace (redo, también el del undo) y después deshace lo no confirmado (undo).
PROMPT   El ROLLBACK no es gratis: deshacer es aplicar cambios, y esos cambios también generan redo.
EXIT
