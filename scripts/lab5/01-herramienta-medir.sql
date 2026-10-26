-- scripts/lab5/01-herramienta-medir.sql — el banco de medida del Lab 5: un paquete que ejecuta una sentencia y dice lo que costó
-- Se ejecuta como SYSDBA: bash scripts/ops/sysdba.sh <este archivo> <evidencia>
-- Vive en un esquema de herramientas propio (LAB_TOOLS, sin contraseña): nada de código de laboratorio dentro de SYS ni de TIENDASUR.
-- Derechos del definidor (AUTHID DEFINER): las sentencias se ejecutan con los privilegios de LAB_TOOLS, que solo alcanzan a TIENDASUR.
-- (Con AUTHID CURRENT_USER, SYS tendría que "prestar" sus privilegios: ORA-06598, INHERIT PRIVILEGES. Oracle lo impide por algo.)
--   lab_tools.medir.consulta('etiqueta', 'SELECT ...')   -> filas, lecturas lógicas y físicas, tiempo y plan real
--   lab_tools.medir.dml('etiqueta', 'UPDATE ...')        -> lecturas, bloques modificados, redo y tiempo; deshace el cambio
-- Cada sentencia se ejecuta dos veces y se mide la segunda (en caliente), como en un banco de pruebas serio.
WHENEVER SQLERROR EXIT FAILURE
ALTER SESSION SET CONTAINER = FREEPDB1;
DECLARE n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM dba_users WHERE username = 'LAB_TOOLS';
  IF n = 0 THEN EXECUTE IMMEDIATE 'CREATE USER lab_tools NO AUTHENTICATION'; END IF;
END;
/
GRANT SELECT ON sys.v_$mystat TO lab_tools;
GRANT SELECT ON sys.v_$statname TO lab_tools;
GRANT SELECT ON sys.v_$sql TO lab_tools;
GRANT SELECT ON sys.v_$sql_plan TO lab_tools;
-- Privilegios de ESQUEMA (23ai): el paquete puede leer y modificar TIENDASUR y nada más
GRANT SELECT ANY TABLE ON SCHEMA tiendasur TO lab_tools;
GRANT INSERT ANY TABLE, UPDATE ANY TABLE, DELETE ANY TABLE ON SCHEMA tiendasur TO lab_tools;
CREATE OR REPLACE PACKAGE lab_tools.medir AUTHID DEFINER AS
  PROCEDURE consulta(p_etiqueta VARCHAR2, p_sql VARCHAR2);
  PROCEDURE dml(p_etiqueta VARCHAR2, p_sql VARCHAR2, p_operaciones NUMBER DEFAULT NULL);
END medir;
/
CREATE OR REPLACE PACKAGE BODY lab_tools.medir AS
  FUNCTION estad(p VARCHAR2) RETURN NUMBER IS x NUMBER;
  BEGIN
    SELECT m.value INTO x FROM sys.v_$mystat m JOIN sys.v_$statname s ON s.statistic# = m.statistic# WHERE s.name = p;
    RETURN x;
  END;
  -- Marca la sentencia con un comentario para encontrarla después en V$SQL
  FUNCTION marcar(p_etiqueta VARCHAR2, p_sql VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN REGEXP_REPLACE(p_sql, '^\s*(\w+)', '\1 /* medir:' || p_etiqueta || ' */', 1, 1);
  END;
  FUNCTION plan(p_etiqueta VARCHAR2) RETURN VARCHAR2 IS v VARCHAR2(4000);
  BEGIN
    SELECT SUBSTR(LISTAGG(TRIM(p.operation || ' ' || p.options || ' ' || p.object_name), ' > ') WITHIN GROUP (ORDER BY p.id), 1, 4000)
      INTO v
      FROM sys.v_$sql_plan p
     WHERE (p.sql_id, p.child_number) = (SELECT sql_id, child_number FROM (
              SELECT sql_id, child_number FROM sys.v_$sql
               WHERE sql_text LIKE '%medir:' || p_etiqueta || ' */%' AND sql_text NOT LIKE '%v_$sql%'
               ORDER BY last_active_time DESC) WHERE ROWNUM = 1)
       AND p.id > 0;
    RETURN v;
  END;
  -- Ejecuta y lee TODAS las filas en lotes de 500, como un cliente real (sin saber cuántas columnas tiene la consulta): DBMS_SQL
  FUNCTION ejecutar(p_sql VARCHAR2) RETURN NUMBER IS
    c INTEGER := DBMS_SQL.OPEN_CURSOR; n INTEGER; filas NUMBER := 0; cols INTEGER; d DBMS_SQL.DESC_TAB; v DBMS_SQL.VARCHAR2_TABLE;
  BEGIN
    DBMS_SQL.PARSE(c, p_sql, DBMS_SQL.NATIVE);
    DBMS_SQL.DESCRIBE_COLUMNS(c, cols, d);
    FOR i IN 1 .. cols LOOP DBMS_SQL.DEFINE_ARRAY(c, i, v, 500, 1); END LOOP;
    n := DBMS_SQL.EXECUTE(c);
    LOOP
      n := DBMS_SQL.FETCH_ROWS(c);
      filas := filas + n;
      EXIT WHEN n < 500;
    END LOOP;
    DBMS_SQL.CLOSE_CURSOR(c);
    RETURN filas;
  END;
  PROCEDURE consulta(p_etiqueta VARCHAR2, p_sql VARCHAR2) IS
    s VARCHAR2(32767) := marcar(p_etiqueta, p_sql); filas NUMBER; lr NUMBER; pr NUMBER; t TIMESTAMP; us NUMBER;
  BEGIN
    filas := ejecutar(s);                                           -- 1.ª ejecución: análisis y calentamiento
    lr := estad('session logical reads'); pr := estad('physical reads'); t := SYSTIMESTAMP;
    filas := ejecutar(s);                                           -- 2.ª ejecución: la que se mide
    us := EXTRACT(SECOND FROM (SYSTIMESTAMP - t)) * 1e6;
    DBMS_OUTPUT.PUT_LINE(RPAD(p_etiqueta, 30) || ' filas=' || LPAD(filas, 7) || '  lecturas lógicas=' || LPAD(estad('session logical reads') - lr, 7)
      || '  físicas=' || LPAD(estad('physical reads') - pr, 5) || '  ' || LPAD(ROUND(us / 1000, 1), 7) || ' ms');
    DBMS_OUTPUT.PUT_LINE(RPAD(' ', 30) || ' plan: ' || plan(p_etiqueta));
  END;
  PROCEDURE dml(p_etiqueta VARCHAR2, p_sql VARCHAR2, p_operaciones NUMBER DEFAULT NULL) IS
    s VARCHAR2(32767) := marcar(p_etiqueta, p_sql); lr NUMBER; rd NUMBER; bc NUMBER; t TIMESTAMP; us NUMBER; filas NUMBER;
  BEGIN
    EXECUTE IMMEDIATE s; ROLLBACK;                                  -- 1.ª ejecución: análisis y calentamiento
    lr := estad('session logical reads'); rd := estad('redo size'); bc := estad('db block changes'); t := SYSTIMESTAMP;
    EXECUTE IMMEDIATE s; filas := NVL(p_operaciones, SQL%ROWCOUNT);   -- un bloque PL/SQL no informa de filas: se indica a mano
    us := EXTRACT(SECOND FROM (SYSTIMESTAMP - t)) * 1e6;
    lr := estad('session logical reads') - lr; bc := estad('db block changes') - bc; rd := estad('redo size') - rd;
    DBMS_OUTPUT.PUT_LINE(RPAD(p_etiqueta, 30) || ' filas=' || LPAD(filas, 6) || '  lecturas lógicas=' || LPAD(lr, 7)
      || '  bloques modificados=' || LPAD(bc, 6) || '  redo=' || LPAD(ROUND(rd / 1024), 6) || ' KB  ' || LPAD(ROUND(us / 1000, 1), 6) || ' ms'
      || CASE WHEN filas > 0 THEN '  | por fila: ' || ROUND(bc / filas, 1) || ' bloques, ' || ROUND(rd / filas) || ' bytes de redo' END);
    ROLLBACK;                                                       -- el banco no deja cambios
  END;
END medir;
/
SHOW ERRORS PACKAGE BODY lab_tools.medir
SET SERVEROUTPUT ON FORMAT WRAPPED LINESIZE 200
PROMPT Prueba del banco de medida:
EXEC lab_tools.medir.consulta('prueba_pk', 'SELECT id_pedido, importe FROM tiendasur.pedido WHERE id_pedido = 4711')
EXIT
