-- scripts/lab4/14-filas-migradas.sql — migración (row migration) y encadenamiento (row chaining): provocarlos, detectarlos, medirlos y corregirlos
-- Se ejecuta como SYSDBA: bash scripts/ops/sysdba.sh <este archivo> <evidencia>
-- Usa el esquema de pruebas que creó 13-capacidad.sql y lo BORRA al final (tablespace TBS_LAB4 incluido).
WHENEVER SQLERROR EXIT FAILURE
SET LINESIZE 170 PAGESIZE 100 FEEDBACK OFF VERIFY OFF TAB OFF
COLUMN table_name FORMAT A12
COLUMN index_name FORMAT A16
COLUMN status FORMAT A9
ALTER SESSION SET CONTAINER = FREEPDB1;
SET SERVEROUTPUT ON FORMAT WRAPPED
-- Requisito: el banco de 13-capacidad.sql. Si este script falló a medias, se borran sus restos para poder repetirlo.
DECLARE n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM dba_users WHERE username = 'LAB4_PRUEBAS';
  IF n = 0 THEN RAISE_APPLICATION_ERROR(-20014, 'Falta el banco LAB4_PRUEBAS: ejecuta antes 13-capacidad.sql (Parte L)'); END IF;
  FOR t IN (SELECT table_name FROM dba_tables WHERE owner = 'LAB4_PRUEBAS' AND table_name IN ('MIGRA', 'CHAINED_ROWS', 'ANCHA')) LOOP
    EXECUTE IMMEDIATE 'DROP TABLE lab4_pruebas.' || t.table_name || ' PURGE';
  END LOOP;
END;
/
PROMPT
PROMPT ===== 1. Tabla con PCTFREE 0 (sin hueco para crecer) y filas cortas =====
CREATE TABLE lab4_pruebas.migra (id NUMBER CONSTRAINT pk_migra PRIMARY KEY, txt VARCHAR2(400)) PCTFREE 0 TABLESPACE tbs_lab4;
INSERT INTO lab4_pruebas.migra SELECT ROWNUM, 'x' FROM dual CONNECT BY LEVEL <= 5000;
COMMIT;
ANALYZE TABLE lab4_pruebas.migra COMPUTE STATISTICS;
SELECT table_name, num_rows, blocks, pct_free, avg_row_len, chain_cnt FROM dba_tables
 WHERE owner = 'LAB4_PRUEBAS' AND table_name = 'MIGRA';
PROMPT (CHAIN_CNT solo lo rellena ANALYZE; DBMS_STATS no lo calcula)
PROMPT
PROMPT ===== 2. Una de cada cinco filas crece de 1 a 300 bytes: no cabe en su bloque y MIGRA =====
UPDATE lab4_pruebas.migra SET txt = RPAD('x', 300, 'x') WHERE MOD(id, 5) = 0;
COMMIT;
ANALYZE TABLE lab4_pruebas.migra COMPUTE STATISTICS;
SELECT table_name, num_rows, blocks, pct_free, avg_row_len, chain_cnt,
       ROUND(100 * chain_cnt / num_rows, 1) AS pct_migradas FROM dba_tables
 WHERE owner = 'LAB4_PRUEBAS' AND table_name = 'MIGRA';
PROMPT
PROMPT ===== 3. Detectarlas fila a fila: ANALYZE ... LIST CHAINED ROWS (tabla CHAINED_ROWS, como utlchain.sql) =====
CREATE TABLE lab4_pruebas.chained_rows (owner_name VARCHAR2(128), table_name VARCHAR2(128), cluster_name VARCHAR2(128),
  partition_name VARCHAR2(128), subpartition_name VARCHAR2(128), head_rowid ROWID, analyze_timestamp DATE);
ANALYZE TABLE lab4_pruebas.migra LIST CHAINED ROWS INTO lab4_pruebas.chained_rows;
SELECT COUNT(*) AS filas_listadas FROM lab4_pruebas.chained_rows;
SET TERMOUT OFF
COLUMN f NEW_VALUE f NOPRINT
COLUMN b NEW_VALUE b NOPRINT
COLUMN s NEW_VALUE s NOPRINT
SELECT TO_CHAR(df.file_id) AS f, TO_CHAR(DBMS_ROWID.ROWID_BLOCK_NUMBER(c.head_rowid, 'BIGFILE')) AS b,
       TO_CHAR(DBMS_ROWID.ROWID_ROW_NUMBER(c.head_rowid)) AS s
  FROM (SELECT head_rowid FROM lab4_pruebas.chained_rows ORDER BY head_rowid FETCH FIRST 1 ROW ONLY) c,
       dba_data_files df WHERE df.tablespace_name = 'TBS_LAB4';
SET TERMOUT ON
SELECT m.id, c.head_rowid AS rowid_cabeza, &f AS archivo, &b AS bloque, &s AS ranura
  FROM lab4_pruebas.chained_rows c JOIN lab4_pruebas.migra m ON m.ROWID = c.head_rowid
 WHERE DBMS_ROWID.ROWID_BLOCK_NUMBER(c.head_rowid, 'BIGFILE') = &b AND DBMS_ROWID.ROWID_ROW_NUMBER(c.head_rowid) = &s;
PROMPT
PROMPT ===== 4. El coste: cada acceso por ROWID a una fila migrada hace una lectura lógica EXTRA =====
DECLARE
  v VARCHAR2(400); n0 NUMBER; n1 NUMBER; l0 NUMBER; l1 NUMBER;
  FUNCTION estad(p VARCHAR2) RETURN NUMBER IS x NUMBER;
  BEGIN SELECT m.value INTO x FROM v$mystat m JOIN v$statname s ON s.statistic# = m.statistic# WHERE s.name = p; RETURN x; END;
BEGIN
  FOR i IN 1 .. 1000 LOOP SELECT txt INTO v FROM lab4_pruebas.migra WHERE id = i; END LOOP;   -- calentamiento
  n0 := estad('table fetch continued row'); l0 := estad('session logical reads');
  FOR i IN 1 .. 1000 LOOP SELECT txt INTO v FROM lab4_pruebas.migra WHERE id = i; END LOOP;
  n1 := estad('table fetch continued row'); l1 := estad('session logical reads');
  DBMS_OUTPUT.PUT_LINE('1000 búsquedas por clave: "table fetch continued row" = ' || (n1 - n0)
       || ' | lecturas lógicas = ' || (l1 - l0) || ' (' || ROUND((l1 - l0) / 1000, 2) || ' por búsqueda)');
END;
/
PROMPT
PROMPT ===== 5. Verlo en el bloque: la cabeza de la fila se queda y apunta a su nuevo sitio (nrid) =====
ALTER SESSION SET tracefile_identifier = 'lab4_migra';
ALTER SYSTEM CHECKPOINT;
ALTER SYSTEM DUMP DATAFILE &f BLOCK &b;
COLUMN tf NEW_VALUE tf NOPRINT
SELECT SUBSTR(value, INSTR(value, '/', -1) + 1) AS tf FROM v$diag_info WHERE name = 'Default Trace File';
SET PAGESIZE 0
WITH t AS (SELECT line_number AS n, payload FROM v$diag_trace_file_contents WHERE trace_filename = '&tf'),
     m AS (SELECT MIN(CASE WHEN payload LIKE 'tab 0, row &s,%' THEN n END) AS fil FROM t)
SELECT RTRIM(t.payload, CHR(10)) AS payload FROM t, m WHERE t.n BETWEEN m.fil AND m.fil + 2 ORDER BY t.n;
SET PAGESIZE 100
PROMPT (fb: --H----- = solo la cabeza (Head): sin F/L la fila no está aquí; nrid = archivo.bloque.ranura donde vive ahora.
PROMPT  Una fila normal tiene fb: --H-FL-- (Head, First y Last piece en el mismo bloque).)
PROMPT
PROMPT ===== 6. ENCADENAMIENTO de verdad: una fila de ~12 000 bytes no cabe en NINGÚN bloque de 8 KB =====
CREATE TABLE lab4_pruebas.ancha (id NUMBER PRIMARY KEY, a VARCHAR2(4000), b VARCHAR2(4000), c VARCHAR2(4000)) TABLESPACE tbs_lab4;
INSERT INTO lab4_pruebas.ancha VALUES (1, RPAD('a', 4000, 'a'), RPAD('b', 4000, 'b'), RPAD('c', 4000, 'c'));
INSERT INTO lab4_pruebas.ancha VALUES (2, 'corta', NULL, NULL);
COMMIT;
ANALYZE TABLE lab4_pruebas.ancha COMPUTE STATISTICS;
SELECT table_name, num_rows, blocks, avg_row_len, chain_cnt FROM dba_tables WHERE owner = 'LAB4_PRUEBAS' AND table_name = 'ANCHA';
PROMPT (Reorganizar NO cura el encadenamiento: solo un bloque mayor (tablespace de 16/32 KB) o rediseñar la tabla)
PROMPT
PROMPT ===== 7. Curar la MIGRACIÓN: ALTER TABLE ... MOVE reescribe las filas (y deja los índices UNUSABLE) =====
ALTER TABLE lab4_pruebas.migra MOVE PCTFREE 20;
SELECT index_name, status FROM dba_indexes WHERE owner = 'LAB4_PRUEBAS' AND table_name = 'MIGRA';
PROMPT (Las filas tienen ROWID nuevo y el índice apunta a los viejos: UNUSABLE. Una consulta que lo necesite fallaría o haría FULL SCAN)
ALTER INDEX lab4_pruebas.pk_migra REBUILD;
SELECT index_name, status FROM dba_indexes WHERE owner = 'LAB4_PRUEBAS' AND table_name = 'MIGRA';
ANALYZE TABLE lab4_pruebas.migra COMPUTE STATISTICS;
SELECT table_name, num_rows, blocks, pct_free, avg_row_len, chain_cnt FROM dba_tables
 WHERE owner = 'LAB4_PRUEBAS' AND table_name = 'MIGRA';
PROMPT (En producción: ALTER TABLE ... MOVE ONLINE mantiene los índices válidos y no bloquea el DML)
PROMPT
PROMPT ===== 8. Limpieza: se borra el banco de pruebas del Lab 4 (esquema y tablespace con su archivo) =====
DROP USER lab4_pruebas CASCADE;
DROP TABLESPACE tbs_lab4 INCLUDING CONTENTS AND DATAFILES;
SELECT COUNT(*) AS tbs_lab4_restantes FROM dba_tablespaces WHERE tablespace_name = 'TBS_LAB4';
EXIT
