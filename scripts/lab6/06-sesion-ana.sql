-- scripts/lab6/06-sesion-ana.sql — lo que vive ANA_GARCIA (secretaría) en su sesión. Lo ejecuta 06-probar-acceso.sh
SET TERMOUT OFF
SET SQLFORMAT DEFAULT
SET TERMOUT ON
SET LINESIZE 150 PAGESIZE 50 FEEDBACK ON
COLUMN role FORMAT A26
COLUMN privilege FORMAT A26
PROMPT -- Roles activos y privilegios de sistema de la sesión
SELECT role FROM session_roles ORDER BY role;
SELECT privilege FROM session_privs ORDER BY privilege;
PROMPT -- Lee Academia por el privilegio de esquema (también aca_matriculas, que nadie le concedió por nombre)
SELECT COUNT(*) AS estudiantes FROM admin_academia.aca_estudiantes;
SELECT COUNT(*) AS matriculas FROM admin_academia.aca_matriculas;
PROMPT -- Puede cambiar el ESTADO de un estudiante...
UPDATE admin_academia.aca_estudiantes SET estado = 'SUSPENDIDO' WHERE estudiante_id = 105;
ROLLBACK;
PROMPT -- ...pero no su nombre (error esperado: falta el privilegio UPDATE sobre esa columna)
UPDATE admin_academia.aca_estudiantes SET nombres = 'Otro' WHERE estudiante_id = 105;
PROMPT -- ...ni borrar (error esperado)
DELETE FROM admin_academia.aca_estudiantes WHERE estudiante_id = 105;
ROLLBACK;
