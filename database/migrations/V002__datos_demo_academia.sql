-- database/migrations/V002__datos_demo_academia.sql
-- Datos de demostración para Academia: 20 000 estudiantes, 40 asignaturas y 60 000 matrículas.
-- Sin datos, la memoria, la caché y los segmentos no tienen nada que enseñar.
-- Idempotente: si ya hay estudiantes, no inserta nada.
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET FEEDBACK ON
ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = admin_academia;
SET SERVEROUTPUT ON
DECLARE
  v_hay NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_hay FROM aca_estudiantes;
  IF v_hay > 0 THEN
    DBMS_OUTPUT.PUT_LINE('V002 ya aplicada (' || v_hay || ' estudiantes): no se inserta nada.');
    RETURN;
  END IF;

  INSERT INTO aca_estudiantes (dni, nombres, apellidos, email_institucional, estado)
  SELECT LPAD(level, 8, '0') || 'X',
         'Nombre' || level,
         'Apellido' || MOD(level, 997),
         'est' || level || '@alu.ucam.edu',
         CASE WHEN MOD(level, 10) = 0 THEN 'EGRESADO'
              WHEN MOD(level, 25) = 0 THEN 'INACTIVO'
              ELSE 'ACTIVO' END
    FROM dual CONNECT BY level <= 20000;

  INSERT INTO aca_asignaturas (codigo, nombre, creditos)
  SELECT 'ABD' || LPAD(level, 3, '0'), 'Asignatura ' || level, MOD(level, 6) + 3
    FROM dual CONNECT BY level <= 40;

  INSERT INTO aca_matriculas (estudiante_id, asignatura_id, periodo)
  SELECT e.estudiante_id, a.asignatura_id, '2026-1'
    FROM aca_estudiantes e
    JOIN (SELECT level AS k FROM dual CONNECT BY level <= 3) n ON 1 = 1
    JOIN aca_asignaturas a ON a.codigo = 'ABD' || LPAD(MOD(e.estudiante_id * 7 + n.k, 40) + 1, 3, '0');

  COMMIT;
  DBMS_STATS.GATHER_SCHEMA_STATS('ADMIN_ACADEMIA');
  DBMS_OUTPUT.PUT_LINE('V002 aplicada.');
END;
/
PROMPT == Verificación ==
SELECT (SELECT COUNT(*) FROM aca_estudiantes) AS estudiantes,
       (SELECT COUNT(*) FROM aca_asignaturas) AS asignaturas,
       (SELECT COUNT(*) FROM aca_matriculas)  AS matriculas FROM dual;
SELECT estudiante_id, dni, estado FROM aca_estudiantes WHERE estudiante_id = 101;
EXIT
