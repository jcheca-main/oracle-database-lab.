-- scripts/lab5/12-sesion-a.sql — SESIÓN A: modifica la fila 101 y tarda en confirmar (transacción abierta 25 s)
SET FEEDBACK ON LINESIZE 140
ALTER SESSION SET CONTAINER = FREEPDB1;
PROMPT [A] UPDATE de la fila 101 a EGRESADO, sin COMMIT todavía
UPDATE admin_academia.aca_estudiantes SET estado = 'EGRESADO' WHERE estudiante_id = 101;
EXEC DBMS_SESSION.SLEEP(25)
COMMIT;
PROMPT [A] COMMIT hecho
EXIT
