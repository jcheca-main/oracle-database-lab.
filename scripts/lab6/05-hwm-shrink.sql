-- scripts/lab6/05-hwm-shrink.sql — borrar no devuelve espacio: la marca de agua alta (HWM) y SHRINK SPACE (Unidad 5, 5.5.6.2)
-- SYSDBA:  bash scripts/ops/sysdba.sh scripts/lab6/05-hwm-shrink.sql "$EVID_LAB6/script/$(ts)_05-hwm-shrink.script.log"
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET LINESIZE 150 PAGESIZE 50 FEEDBACK ON
ALTER SESSION SET CONTAINER = FREEPDB1;
COLUMN momento FORMAT A22
PROMPT == 1. Antes: 20 000 filas ==
SELECT 'antes del DELETE' AS momento, (SELECT COUNT(*) FROM carga_hist.registro) AS filas, blocks AS bloques, ROUND(bytes / 1048576, 1) AS mb
  FROM dba_segments WHERE owner = 'CARGA_HIST' AND segment_name = 'REGISTRO';
PROMPT == 2. Se borra el 90 % (el histórico antiguo) ==
DELETE FROM carga_hist.registro WHERE MOD(id, 10) <> 0;
COMMIT;
SELECT 'tras el DELETE' AS momento, (SELECT COUNT(*) FROM carga_hist.registro) AS filas, blocks AS bloques, ROUND(bytes / 1048576, 1) AS mb
  FROM dba_segments WHERE owner = 'CARGA_HIST' AND segment_name = 'REGISTRO';
PROMPT -- El segmento NO ha encogido: los bloques siguen por debajo de la HWM (medio vacíos) y la cuota sigue consumida
PROMPT == 3. Compactar en línea: SHRINK SPACE mueve filas (por eso exige ROW MOVEMENT) y baja la HWM ==
ALTER TABLE carga_hist.registro ENABLE ROW MOVEMENT;
ALTER TABLE carga_hist.registro SHRINK SPACE;
SELECT 'tras SHRINK SPACE' AS momento, (SELECT COUNT(*) FROM carga_hist.registro) AS filas, blocks AS bloques, ROUND(bytes / 1048576, 1) AS mb
  FROM dba_segments WHERE owner = 'CARGA_HIST' AND segment_name = 'REGISTRO';
COLUMN username FORMAT A10
SELECT username, ROUND(bytes / 1048576, 1) AS cuota_usada_mb FROM dba_ts_quotas WHERE username = 'CARGA_HIST';
EXIT
