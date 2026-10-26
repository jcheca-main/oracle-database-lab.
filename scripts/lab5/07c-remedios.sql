-- scripts/lab5/07c-remedios.sql — COALESCE, SHRINK SPACE o REBUILD: qué hace cada uno, cuánto recupera y qué bloquea
-- Se ejecuta desde 07-divisiones-y-cola.sh, después de dibujar la cola. Al final borra el esquema de pruebas LAB5_PRUEBAS.
WHENEVER SQLERROR EXIT FAILURE
SET LINESIZE 170 PAGESIZE 100 FEEDBACK OFF VERIFY OFF TAB OFF
COLUMN paso FORMAT A34
ALTER SESSION SET CONTAINER = FREEPDB1;
SET SERVEROUTPUT ON FORMAT WRAPPED
CREATE TABLE lab5_pruebas.medidas (paso VARCHAR2(34), hojas NUMBER, borradas NUMBER, mb_segmento NUMBER, lecturas_siguiente NUMBER);
DECLARE
  PROCEDURE medir(p VARCHAR2) IS h NUMBER; d NUMBER; mb NUMBER; lr NUMBER; v NUMBER;
    FUNCTION estad RETURN NUMBER IS x NUMBER;
    BEGIN SELECT m.value INTO x FROM v$mystat m JOIN v$statname s ON s.statistic# = m.statistic# WHERE s.name = 'session logical reads'; RETURN x; END;
  BEGIN
    EXECUTE IMMEDIATE 'ANALYZE INDEX lab5_pruebas.ix_cola VALIDATE STRUCTURE';   -- cuenta TODAS las hojas, también las vacías
    SELECT lf_blks, del_lf_rows INTO h, d FROM index_stats;
    SELECT ROUND(bytes / 1048576, 2) INTO mb FROM dba_segments WHERE owner = 'LAB5_PRUEBAS' AND segment_name = 'IX_COLA';
    SELECT id INTO v FROM lab5_pruebas.cola ORDER BY id FETCH FIRST 1 ROWS ONLY;
    lr := estad; SELECT id INTO v FROM lab5_pruebas.cola ORDER BY id FETCH FIRST 1 ROWS ONLY; lr := estad - lr;
    INSERT INTO lab5_pruebas.medidas VALUES (p, h, d, mb, lr); COMMIT;
  END;
BEGIN
  medir('0. cola degradada');
  EXECUTE IMMEDIATE 'ALTER INDEX lab5_pruebas.ix_cola COALESCE';
  medir('1. tras COALESCE');
  EXECUTE IMMEDIATE 'ALTER INDEX lab5_pruebas.ix_cola SHRINK SPACE';
  medir('2. tras SHRINK SPACE');
  EXECUTE IMMEDIATE 'ALTER INDEX lab5_pruebas.ix_cola REBUILD ONLINE';
  medir('3. tras REBUILD ONLINE');
END;
/
PROMPT
PROMPT ===== Remedios para el patrón cola, medidos =====
SELECT paso, hojas, borradas, mb_segmento, lecturas_siguiente AS lecturas_siguiente_mensaje FROM lab5_pruebas.medidas ORDER BY paso;
PROMPT
PROMPT (Ojo: DBA_INDEXES.LEAF_BLOCKS, que rellena DBMS_STATS, no cuenta las hojas VACÍAS: para verlas hace falta VALIDATE STRUCTURE o el gráfico)
PROMPT   COALESCE        fusiona hojas vecinas medio vacías dentro del índice. En línea, sin bloqueo. NO devuelve espacio al tablespace.
PROMPT   SHRINK SPACE    COALESCE + devuelve los bloques sobrantes al tablespace (baja la marca de agua). En línea.
PROMPT   REBUILD ONLINE  construye un índice nuevo leyendo el viejo y lo cambia al final. Necesita espacio doble y genera mucho redo.
PROMPT   Regla profesional: medir antes (gráfico o INDEX_STATS); COALESCE para la cola, REBUILD solo con una causa concreta y medida.
PROMPT   Y la cura de verdad del patrón cola es de DISEÑO: particionar por fecha y vaciar particiones enteras (DROP/TRUNCATE PARTITION).
EXIT
