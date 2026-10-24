-- scripts/lab4/13-capacidad.sql — factor de bloqueo, número de páginas y coste real de las lecturas (Unidad 3, 3.1.7 y 3.1.8)
-- Se ejecuta como SYSDBA: bash scripts/ops/sysdba.sh <este archivo> <evidencia>
-- Crea el tablespace y el esquema de pruebas del Lab 4 (TBS_LAB4 / LAB4_PRUEBAS). 14-filas-migradas.sql los borra al final.
-- ALTER SYSTEM FLUSH BUFFER_CACHE vacía la caché: SOLO en laboratorio, NUNCA en producción.
WHENEVER SQLERROR EXIT FAILURE
SET LINESIZE 170 PAGESIZE 100 FEEDBACK OFF VERIFY OFF TAB OFF
COLUMN metrica FORMAT A46
COLUMN valor FORMAT A40
ALTER SESSION SET CONTAINER = FREEPDB1;
SET SERVEROUTPUT ON FORMAT WRAPPED
PROMPT
PROMPT ===== 1. ACA_ESTUDIANTES: lo que dicen las estadísticas (r filas, R bytes por fila, b bloques) =====
EXEC DBMS_STATS.GATHER_TABLE_STATS('ADMIN_ACADEMIA', 'ACA_ESTUDIANTES')
SELECT t.num_rows AS r, t.avg_row_len AS r_bytes, t.blocks AS bloques_bajo_hwm, t.pct_free, t.ini_trans,
       s.blocks AS bloques_asignados, ts.block_size AS b_bytes
  FROM dba_tables t JOIN dba_segments s ON s.owner = t.owner AND s.segment_name = t.table_name
  JOIN dba_tablespaces ts ON ts.tablespace_name = t.tablespace_name
 WHERE t.owner = 'ADMIN_ACADEMIA' AND t.table_name = 'ACA_ESTUDIANTES';
PROMPT
PROMPT ===== 2. Factor de bloqueo MEDIDO: filas por bloque, contando de verdad =====
SELECT COUNT(*) AS bloques_con_filas, MIN(n) AS min_filas, ROUND(AVG(n), 1) AS media_filas, MAX(n) AS max_filas
  FROM (SELECT DBMS_ROWID.ROWID_BLOCK_NUMBER(ROWID, 'BIGFILE') AS blk, COUNT(*) AS n
          FROM admin_academia.aca_estudiantes GROUP BY DBMS_ROWID.ROWID_BLOCK_NUMBER(ROWID, 'BIGFILE'));
PROMPT
PROMPT ===== 3. Factor de bloqueo CALCULADO y número de páginas (fórmulas de la Unidad 3, 3.1.7) =====
DECLARE
  b_blk CONSTANT NUMBER := 8192;
  h_u3  CONSTANT NUMBER := 96;          -- cabecera del ejemplo de la Unidad 3
  h_ora CONSTANT NUMBER := 104 + 18;    -- Oracle: cabecera fija con 2 ITL (104) + cabecera de datos (18)
  r NUMBER; rlen NUMBER; pf NUMBER; b NUMBER;
  bfr_u3 NUMBER; bfr_ora NUMBER;
BEGIN
  SELECT num_rows, avg_row_len, pct_free, blocks INTO r, rlen, pf, b FROM dba_tables
   WHERE owner = 'ADMIN_ACADEMIA' AND table_name = 'ACA_ESTUDIANTES';
  bfr_u3  := FLOOR((b_blk - h_u3) * (1 - pf / 100) / rlen);
  bfr_ora := FLOOR((b_blk - h_ora) * (1 - pf / 100) / (rlen + 2));   -- +2: entrada del directorio de filas por fila
  DBMS_OUTPUT.PUT_LINE('bfr (Unidad 3)  = floor((8192-96)*(1-' || pf || '%)/' || rlen || ')        = ' || bfr_u3
                       || ' filas/bloque -> b = ceil(' || r || '/' || bfr_u3 || ') = ' || CEIL(r / bfr_u3) || ' bloques');
  DBMS_OUTPUT.PUT_LINE('bfr (Oracle)    = floor((8192-122)*(1-' || pf || '%)/(' || rlen || '+2))   = ' || bfr_ora
                       || ' filas/bloque -> b = ceil(' || r || '/' || bfr_ora || ') = ' || CEIL(r / bfr_ora) || ' bloques');
  DBMS_OUTPUT.PUT_LINE('b real (estadísticas, bajo la HWM)                           = ' || b || ' bloques');
END;
/
PROMPT
PROMPT ===== 4. Banco de medida: tablespace y esquema de pruebas del Lab 4 (dentro del volumen) =====
DROP USER IF EXISTS lab4_pruebas CASCADE;
DROP TABLESPACE IF EXISTS tbs_lab4 INCLUDING CONTENTS AND DATAFILES;
CREATE BIGFILE TABLESPACE tbs_lab4 DATAFILE '/opt/oracle/oradata/FREE/FREEPDB1/lab4_pruebas01.dbf'
  SIZE 64M AUTOEXTEND ON NEXT 32M MAXSIZE 512M;
CREATE USER lab4_pruebas NO AUTHENTICATION DEFAULT TABLESPACE tbs_lab4 QUOTA UNLIMITED ON tbs_lab4;
CREATE TABLE lab4_pruebas.lecturas PCTFREE 10 AS
  SELECT ROWNUM AS id, MOD(ROWNUM, 1000) AS grupo, RPAD('x', 60, 'x') AS relleno, SYSDATE - MOD(ROWNUM, 3650) AS fecha
    FROM dual CONNECT BY LEVEL <= 400000;
ALTER TABLE lab4_pruebas.lecturas ADD CONSTRAINT pk_lecturas PRIMARY KEY (id);
EXEC DBMS_STATS.GATHER_TABLE_STATS('LAB4_PRUEBAS', 'LECTURAS')
SELECT num_rows AS r, avg_row_len AS r_bytes, blocks AS b, ROUND(blocks * 8192 / 1048576, 1) AS mb
  FROM dba_tables WHERE owner = 'LAB4_PRUEBAS' AND table_name = 'LECTURAS';
PROMPT
PROMPT ===== 5. Coste MEDIDO de una lectura lógica, una física aleatoria y una lectura secuencial =====
DECLARE
  lr0 NUMBER; pr0 NUMBER; rq0 NUMBER; mb0 NUMBER; c0 NUMBER; n NUMBER; peticiones NUMBER; v VARCHAR2(60);
  t0 TIMESTAMP; us NUMBER; lat_us NUMBER; seq_us NUMBER; bloques NUMBER; bfr NUMBER; filas NUMBER;
  FUNCTION estad(p VARCHAR2) RETURN NUMBER IS x NUMBER;
  BEGIN SELECT m.value INTO x FROM v$mystat m JOIN v$statname s ON s.statistic# = m.statistic# WHERE s.name = p; RETURN x; END;
  FUNCTION micros(t TIMESTAMP) RETURN NUMBER IS d INTERVAL DAY TO SECOND := SYSTIMESTAMP - t;
  BEGIN RETURN EXTRACT(SECOND FROM d) * 1e6 + EXTRACT(MINUTE FROM d) * 60e6; END;
BEGIN
  SELECT blocks, num_rows INTO bloques, filas FROM dba_tables WHERE owner = 'LAB4_PRUEBAS' AND table_name = 'LECTURAS';
  bfr := ROUND(filas / bloques);
  -- 5a. Lectura LÓGICA: 100 000 búsquedas por clave primaria con todo ya en caché (calentamiento previo)
  FOR i IN 1 .. 2000 LOOP SELECT relleno INTO v FROM lab4_pruebas.lecturas WHERE id = i * 200; END LOOP;
  lr0 := estad('session logical reads'); c0 := DBMS_UTILITY.GET_CPU_TIME;
  FOR i IN 1 .. 100000 LOOP SELECT relleno INTO v FROM lab4_pruebas.lecturas WHERE id = MOD(i, 2000) * 200 + 200; END LOOP;
  n := estad('session logical reads') - lr0;
  DBMS_OUTPUT.PUT_LINE('5a. LÓGICA    : ' || n || ' lecturas lógicas (' || n / 100000 || ' por búsqueda) en '
       || (DBMS_UTILITY.GET_CPU_TIME - c0) * 10 || ' ms de CPU -> '
       || ROUND((DBMS_UTILITY.GET_CPU_TIME - c0) * 10000 / n, 2) || ' µs por lectura lógica');
  -- 5b. Lectura FÍSICA aleatoria: caché vacía y 2000 filas repartidas, de una en una (índice + tabla)
  EXECUTE IMMEDIATE 'ALTER SYSTEM FLUSH BUFFER_CACHE';
  pr0 := estad('physical reads'); t0 := SYSTIMESTAMP;
  FOR i IN 1 .. 2000 LOOP SELECT relleno INTO v FROM lab4_pruebas.lecturas WHERE id = i * 197; END LOOP;
  us := micros(t0); n := estad('physical reads') - pr0;
  lat_us := ROUND(us / n, 1);   -- tiempo de pared por lectura: incluye la CPU, así que es una cota superior de lat
  DBMS_OUTPUT.PUT_LINE('5b. ALEATORIA : ' || n || ' lecturas físicas de 1 bloque (índice + tabla) en ' || ROUND(us / 1000, 1)
       || ' ms -> lat = ' || lat_us || ' µs por lectura física');
  -- 5c. Lectura SECUENCIAL multibloque: caché vacía y recorrido completo
  EXECUTE IMMEDIATE 'ALTER SYSTEM FLUSH BUFFER_CACHE';
  pr0 := estad('physical reads'); rq0 := estad('physical read total IO requests');
  mb0 := estad('physical read total multi block requests'); t0 := SYSTIMESTAMP;
  SELECT /*+ FULL(l) */ COUNT(*) INTO n FROM lab4_pruebas.lecturas l WHERE relleno IS NOT NULL;
  seq_us := micros(t0);
  n := estad('physical reads') - pr0; peticiones := estad('physical read total IO requests') - rq0;
  DBMS_OUTPUT.PUT_LINE('5c. SECUENCIAL: ' || n || ' bloques en ' || peticiones || ' peticiones ('
       || (estad('physical read total multi block requests') - mb0) || ' multibloque, ~' || ROUND(n / peticiones)
       || ' bloques/petición) en ' || ROUND(seq_us / 1000) || ' ms -> Bw = ' || ROUND(n * 8192 / 1048576 / (seq_us / 1e6)) || ' MB/s');
  DBMS_OUTPUT.PUT_LINE('');
  DBMS_OUTPUT.PUT_LINE('5d. PREDICCIÓN frente a MEDIDA (Unidad 3, 3.1.8), con b = ' || n || ' bloques:');
  DBMS_OUTPUT.PUT_LINE('    T_secuencial medido               = ' || ROUND(seq_us / 1000, 1) || ' ms');
  DBMS_OUTPUT.PUT_LINE('    T_aleatorio  = b x lat            = ' || n || ' x ' || lat_us || ' µs = '
       || ROUND(n * lat_us / 1000, 1) || ' ms (' || ROUND(n * lat_us / seq_us, 1) || ' veces el secuencial)');
  DBMS_OUTPUT.PUT_LINE('    Con un disco HDD (lat ~ 5 ms)     = ' || ROUND(n * 5 / 1000, 1) || ' s;  con SSD (lat ~ 0,1 ms) = '
       || ROUND(n * 0.1) || ' ms');
  DBMS_OUTPUT.PUT_LINE('    c_sec / c_aleat por bloque        = ' || ROUND((seq_us / n) / NULLIF(lat_us, 0), 3));
  DBMS_OUTPUT.PUT_LINE('    Umbral k/r < (1/bfr) x cociente   = (1/' || bfr || ') x ' || ROUND((seq_us / n) / NULLIF(lat_us, 0), 3)
       || ' = ' || ROUND(100 * (seq_us / n) / NULLIF(lat_us, 0) / bfr, 2) || ' % de las filas: por encima, el recorrido completo gana');
END;
/
PROMPT (OJO: en este contenedor la "lectura física" de Oracle la sirve muchas veces la caché de páginas de Linux, no el disco:
PROMPT  FLUSH BUFFER_CACHE vacía la caché de Oracle, no la del sistema operativo. Por eso lat sale en microsegundos.
PROMPT  En producción con almacenamiento real se mide igual y sale del orden de 0,1-10 ms: el método es el que importa.)
PROMPT
PROMPT ===== 6. Las mismas latencias vistas por toda la instancia desde el arranque (v$system_event) =====
COLUMN event FORMAT A30
SELECT event, total_waits AS esperas, ROUND(time_waited_micro / NULLIF(total_waits, 0)) AS us_por_espera
  FROM v$system_event WHERE event IN ('db file sequential read', 'db file scattered read', 'direct path read')
 ORDER BY event;
PROMPT ('db file sequential read' = lectura física de UN bloque; 'scattered' = multibloque a la caché;
PROMPT  'direct path read' = multibloque a la PGA, saltándose la caché: el "bypass" de la Unidad 3, 3.1.8)
EXIT
