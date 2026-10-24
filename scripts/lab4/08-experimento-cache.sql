-- scripts/lab4/08-experimento-cache.sql — el Buffer Cache en acción: lectura en frío frente a lectura en caliente
-- Se ejecuta como SYSDBA: bash scripts/ops/sysdba.sh <este archivo> <evidencia>
-- ALTER SYSTEM FLUSH BUFFER_CACHE vacía la caché: SOLO en laboratorio, NUNCA en producción.
WHENEVER SQLERROR EXIT FAILURE
SET LINESIZE 160 PAGESIZE 100 FEEDBACK OFF
COLUMN table_name FORMAT A16
COLUMN object_name FORMAT A16
ALTER SESSION SET CONTAINER = FREEPDB1;
-- SERVEROUTPUT se activa DESPUÉS de cambiar de contenedor (si no, no se ve la salida)
SET SERVEROUTPUT ON
PROMPT
PROMPT ===== 1. La tabla del ejemplo continuo: cuántos bloques ocupa =====
SELECT table_name, num_rows, blocks, avg_row_len FROM dba_tables
 WHERE owner = 'ADMIN_ACADEMIA' AND table_name = 'ACA_ESTUDIANTES';
PROMPT
PROMPT ===== 2. Vaciar la caché (solo laboratorio) =====
ALTER SYSTEM FLUSH BUFFER_CACHE;
PROMPT
PROMPT ===== 3. Misma consulta dos veces: lecturas lógicas (memoria) y físicas (disco) de ESTA sesión =====
DECLARE
  FUNCTION estad(p_nombre VARCHAR2) RETURN NUMBER IS
    v NUMBER;
  BEGIN
    SELECT m.value INTO v FROM v$mystat m JOIN v$statname n ON n.statistic# = m.statistic#
     WHERE n.name = p_nombre;
    RETURN v;
  END;
  PROCEDURE ronda(p_titulo VARCHAR2) IS
    l0 NUMBER := estad('session logical reads');
    f0 NUMBER := estad('physical reads');
    n  NUMBER;
  BEGIN
    SELECT /*+ FULL(e) */ COUNT(*) INTO n FROM admin_academia.aca_estudiantes e WHERE estado = 'ACTIVO';
    DBMS_OUTPUT.PUT_LINE(RPAD(p_titulo, 25) || ' filas ACTIVO=' || n
      || ' | lecturas lógicas=' || (estad('session logical reads') - l0)
      || ' | lecturas físicas=' || (estad('physical reads') - f0));
  END;
BEGIN
  ronda('Ronda 1 (caché fría)');
  ronda('Ronda 2 (caché caliente)');
END;
/
PROMPT
PROMPT ===== 4. Los bloques de la tabla que ahora viven en el Buffer Cache (v$bh) =====
SELECT o.object_name, COUNT(*) AS bloques_en_cache
  FROM v$bh b JOIN dba_objects o ON o.data_object_id = b.objd
 WHERE o.owner = 'ADMIN_ACADEMIA' AND o.object_name = 'ACA_ESTUDIANTES' AND b.status <> 'free'
 GROUP BY o.object_name;
EXIT
