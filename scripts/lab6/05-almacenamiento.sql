-- scripts/lab6/05-almacenamiento.sql — tablespaces, medir bien, segmentos y cuotas (Unidad 5, 5.5.1 a 5.5.7)
-- SYSDBA:  bash scripts/ops/sysdba.sh scripts/lab6/05-almacenamiento.sql "$EVID_LAB6/script/$(ts)_05-almacenamiento.script.log"
-- Crea TBS_ACADEMIA_HIST (histórico de Academia) y el esquema CARGA_HIST, que lo usa. Repetible.
SET LINESIZE 160 PAGESIZE 100 FEEDBACK ON
ALTER SESSION SET CONTAINER = FREEPDB1;
SET SERVEROUTPUT ON
COLUMN tablespace_name FORMAT A18
COLUMN segment_name FORMAT A26
COLUMN segment_type FORMAT A10
COLUMN username FORMAT A10
COLUMN file_name FORMAT A58
PROMPT == 1. Un tablespace nuevo con todas sus decisiones: ruta explícita, tamaño inicial y crecimiento CON TECHO ==
DECLARE n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM dba_tablespaces WHERE tablespace_name = 'TBS_ACADEMIA_HIST';
  IF n = 0 THEN
    EXECUTE IMMEDIATE q'[CREATE TABLESPACE tbs_academia_hist
      DATAFILE '/opt/oracle/oradata/FREE/FREEPDB1/academia_hist01.dbf' SIZE 10M AUTOEXTEND ON NEXT 5M MAXSIZE 40M]';
    DBMS_OUTPUT.PUT_LINE('TBS_ACADEMIA_HIST creado');
  ELSE
    DBMS_OUTPUT.PUT_LINE('TBS_ACADEMIA_HIST ya existía');
  END IF;
END;
/
SELECT tablespace_name, bigfile, extent_management, allocation_type, segment_space_management
  FROM dba_tablespaces WHERE tablespace_name IN ('TBS_ACADEMIA', 'TBS_ACADEMIA_HIST') ORDER BY 1;
PROMPT == 2. Medir bien: asignado, libre dentro de lo asignado y máximo alcanzable (no son lo mismo) ==
SELECT df.tablespace_name, ROUND(SUM(df.bytes) / 1048576) AS asignado_mb, ROUND(MAX(fs.libre) / 1048576, 1) AS libre_mb,
       ROUND(SUM(DECODE(df.autoextensible, 'YES', df.maxbytes, df.bytes)) / 1048576) AS max_mb
  FROM dba_data_files df
  LEFT JOIN (SELECT tablespace_name, SUM(bytes) AS libre FROM dba_free_space GROUP BY tablespace_name) fs
    ON fs.tablespace_name = df.tablespace_name
 WHERE df.tablespace_name IN ('TBS_ACADEMIA', 'TBS_ACADEMIA_HIST')
 GROUP BY df.tablespace_name ORDER BY 1;
SELECT tablespace_name, used_space AS bloques_usados, tablespace_size AS bloques_max, ROUND(used_percent, 2) AS pct_sobre_max
  FROM dba_tablespace_usage_metrics WHERE tablespace_name IN ('TBS_ACADEMIA', 'TBS_ACADEMIA_HIST') ORDER BY 1;
PROMPT == 3. Los tablespaces no crecen solos: crecen sus segmentos. ¿Quién ocupa TBS_ACADEMIA? ==
SELECT segment_name, segment_type, ROUND(bytes / 1048576, 2) AS mb, blocks, extents
  FROM dba_segments WHERE tablespace_name = 'TBS_ACADEMIA' ORDER BY bytes DESC FETCH FIRST 6 ROWS ONLY;
PROMPT == 4. Un esquema de solo esquema SIN cuota en su tablespace por defecto ==
DECLARE n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM dba_users WHERE username = 'CARGA_HIST';
  IF n > 0 THEN EXECUTE IMMEDIATE 'DROP USER carga_hist CASCADE'; END IF;   -- repetible: se parte de cero
  EXECUTE IMMEDIATE 'CREATE USER carga_hist NO AUTHENTICATION DEFAULT TABLESPACE tbs_academia_hist';
END;
/
CREATE TABLE carga_hist.registro (id NUMBER, momento TIMESTAMP DEFAULT SYSTIMESTAMP, relleno CHAR(1000));
PROMPT -- La tabla existe... pero todavía no tiene segmento (creación diferida): no ocupa nada
SELECT COUNT(*) AS segmentos_de_carga_hist FROM dba_segments WHERE owner = 'CARGA_HIST';
PROMPT -- Primer INSERT: ahora sí hace falta un segmento, y el dueño no tiene cuota (error esperado: ORA-01950)
INSERT INTO carga_hist.registro (id, relleno) VALUES (1, 'x');
PROMPT == 5. Cuota de 2 MB: la paga el DUEÑO del segmento, aunque inserte otro (error esperado: ORA-01536) ==
ALTER USER carga_hist QUOTA 2M ON tbs_academia_hist;
INSERT INTO carga_hist.registro (id, relleno) SELECT level, 'x' FROM dual CONNECT BY level <= 5000;
ROLLBACK;
COLUMN max_bytes FORMAT 999999999
SELECT username, tablespace_name, bytes, max_bytes, blocks, max_blocks FROM dba_ts_quotas WHERE username = 'CARGA_HIST';
PROMPT == 6. Las cuotas no se aplican al tablespace temporal (error esperado: ORA-30041) ==
ALTER USER carga_hist QUOTA 10M ON temp;
PROMPT == 7. Que avise ANTES de llenarse: umbral de alerta para TBS_ACADEMIA_HIST (en la Parte B salía NONE) ==
BEGIN
  DBMS_SERVER_ALERT.SET_THRESHOLD(
    metrics_id              => DBMS_SERVER_ALERT.TABLESPACE_PCT_FULL,
    warning_operator        => DBMS_SERVER_ALERT.OPERATOR_GE, warning_value  => '80',
    critical_operator       => DBMS_SERVER_ALERT.OPERATOR_GE, critical_value => '95',
    observation_period      => 1, consecutive_occurrences => 1, instance_name => NULL,
    object_type             => DBMS_SERVER_ALERT.OBJECT_TYPE_TABLESPACE, object_name => 'TBS_ACADEMIA_HIST');
END;
/
COLUMN op FORMAT A12
COLUMN aviso FORMAT A6
COLUMN critico FORMAT A7
SELECT tablespace_name, warning_operator AS op, warning_value AS aviso, critical_value AS critico
  FROM dba_tablespace_thresholds WHERE tablespace_name IN ('TBS_ACADEMIA', 'TBS_ACADEMIA_HIST') ORDER BY 1;
EXIT
