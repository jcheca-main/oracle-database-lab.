-- scripts/lab6/06-app-sigue.sql — validación: tras pasar a un rol, la aplicación sigue funcionando (y no puede más de lo previsto)
SET TERMOUT OFF
SET SQLFORMAT DEFAULT
SET TERMOUT ON
SET FEEDBACK ON
COLUMN role FORMAT A20
SELECT role FROM session_roles;
SELECT COUNT(*) AS estudiantes FROM admin_academia.aca_estudiantes WHERE estado = 'ACTIVO';
UPDATE admin_academia.aca_estudiantes SET estado = estado WHERE estudiante_id = 101;
ROLLBACK;
PROMPT -- Ya no puede insertar en el histórico (el permiso temporal de la Parte F se retiró): error esperado
INSERT INTO carga_hist.registro (id, relleno) VALUES (-1, 'x');
