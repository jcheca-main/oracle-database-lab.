-- scripts/lab4/03-verificar-negocio.sql — ¿siguen ahí los cinco entornos de negocio y sus datos?
WHENEVER SQLERROR EXIT FAILURE
SET LINESIZE 160 PAGESIZE 100 FEEDBACK OFF
COLUMN tablespace_name FORMAT A14
COLUMN file_name FORMAT A50
COLUMN online_status FORMAT A8
COLUMN owner FORMAT A16
ALTER SESSION SET CONTAINER = FREEPDB1;
SELECT tablespace_name, file_name, ROUND(bytes / 1048576) AS mb, online_status
  FROM dba_data_files WHERE tablespace_name LIKE 'TBS\_%' ESCAPE '\' ORDER BY tablespace_name;
SELECT owner, COUNT(*) AS tablas FROM dba_tables
 WHERE owner LIKE 'ADMIN\_%' ESCAPE '\' GROUP BY owner ORDER BY owner;
SELECT (SELECT COUNT(*) FROM admin_academia.aca_estudiantes) AS estudiantes,
       (SELECT estado FROM admin_academia.aca_estudiantes WHERE estudiante_id = 101) AS estado_fila_101
  FROM dual;
EXIT
