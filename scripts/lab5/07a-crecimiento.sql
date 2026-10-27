-- scripts/lab5/07a-crecimiento.sql — cómo crece un índice: claves al azar (divisiones 50/50) frente a claves crecientes (divisiones 90/10)
-- Se ejecuta desde 07-divisiones-y-cola.sh. Crea el esquema de pruebas LAB5_PRUEBAS (lo borra 07c).
WHENEVER SQLERROR EXIT FAILURE
SET LINESIZE 170 PAGESIZE 100 FEEDBACK OFF VERIFY OFF TAB OFF
COLUMN index_name FORMAT A14
ALTER SESSION SET CONTAINER = FREEPDB1;
SET SERVEROUTPUT ON FORMAT WRAPPED
DROP USER IF EXISTS lab5_pruebas CASCADE;
CREATE USER lab5_pruebas NO AUTHENTICATION DEFAULT TABLESPACE tbs_tiendasur QUOTA UNLIMITED ON tbs_tiendasur;
GRANT SELECT ANY TABLE ON SCHEMA lab5_pruebas TO lab_tools;
CREATE TABLE lab5_pruebas.azar (k NUMBER, relleno CHAR(20));
CREATE INDEX lab5_pruebas.ix_azar ON lab5_pruebas.azar (k);
CREATE TABLE lab5_pruebas.creciente (k NUMBER NOT NULL, relleno CHAR(20));
CREATE INDEX lab5_pruebas.ix_creciente ON lab5_pruebas.creciente (k);
CREATE TABLE lab5_pruebas.invertida (k NUMBER, relleno CHAR(20));
CREATE INDEX lab5_pruebas.ix_invertida ON lab5_pruebas.invertida (k) REVERSE;
PROMPT
PROMPT ===== 1. 200 000 inserciones de una fila en cada tabla, contando las divisiones de hoja (leaf node splits) =====
DECLARE
  s0 NUMBER; s9 NUMBER;
  FUNCTION estad(p VARCHAR2) RETURN NUMBER IS x NUMBER;
  BEGIN SELECT m.value INTO x FROM v$mystat m JOIN v$statname s ON s.statistic# = m.statistic# WHERE s.name = p; RETURN x; END;
  PROCEDURE informe(t VARCHAR2) IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE(RPAD(t, 34) || ' divisiones de hoja = ' || LPAD(estad('leaf node splits') - s0, 5)
      || '   de ellas 90/10 = ' || LPAD(estad('leaf node 90-10 splits') - s9, 5));
  END;
BEGIN
  s0 := estad('leaf node splits'); s9 := estad('leaf node 90-10 splits');
  FOR i IN 1 .. 200000 LOOP INSERT INTO lab5_pruebas.azar VALUES (ORA_HASH(i, 4294967295, 7), 'x'); END LOOP;
  COMMIT; informe('AZAR (claves aleatorias)');
  s0 := estad('leaf node splits'); s9 := estad('leaf node 90-10 splits');
  FOR i IN 1 .. 200000 LOOP INSERT INTO lab5_pruebas.creciente VALUES (i, 'x'); END LOOP;
  COMMIT; informe('CRECIENTE (secuencia, fecha...)');
  s0 := estad('leaf node splits'); s9 := estad('leaf node 90-10 splits');
  FOR i IN 1 .. 200000 LOOP INSERT INTO lab5_pruebas.invertida VALUES (i, 'x'); END LOOP;
  COMMIT; informe('CRECIENTE con índice REVERSE');
END;
/
PROMPT (90/10: al llenarse la hoja de la derecha, Oracle abre una nueva casi vacía y deja la vieja LLENA. 50/50: reparte a medias)
PROMPT
PROMPT ===== 2. Resultado: hojas y llenado de cada índice =====
BEGIN
  FOR t IN (SELECT table_name FROM dba_tables WHERE owner = 'LAB5_PRUEBAS') LOOP
    DBMS_STATS.GATHER_TABLE_STATS('LAB5_PRUEBAS', t.table_name, cascade => TRUE);
  END LOOP;
END;
/
SELECT index_name, index_type, leaf_blocks AS hojas, ROUND(num_rows / leaf_blocks) AS entradas_por_hoja FROM dba_indexes
 WHERE owner = 'LAB5_PRUEBAS' ORDER BY leaf_blocks;
PROMPT (Teoría, Unidad 3: con inserciones al azar un B-tree se estabiliza en torno al 69 % de llenado (ln 2). Compruébalo en el gráfico)
PROMPT
PROMPT ===== 3. El precio del índice REVERSE: reparte la "hoja caliente" de la derecha, pero ya no sirve para rangos =====
EXEC lab_tools.medir.consulta('rango con índice normal', 'SELECT COUNT(relleno) FROM lab5_pruebas.creciente WHERE k BETWEEN 1000 AND 1100')
EXEC lab_tools.medir.consulta('rango con índice REVERSE', 'SELECT COUNT(relleno) FROM lab5_pruebas.invertida WHERE k BETWEEN 1000 AND 1100')
EXIT
