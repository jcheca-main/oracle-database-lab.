-- scripts/lab6/07-archivos-criticos.sql — inventario de los archivos sin los que la base no arranca o pierde datos (Unidad 5, 5.7.3)
-- Solo lectura:  bash scripts/ops/ro.sh scripts/lab6/07-archivos-criticos.sql
@scripts/ops/marca
@scripts/ops/cabecera 07-archivos-criticos
SPOOL docs/bitacora/lab6/evidencia/spool/&marca._07-archivos-criticos.spool.log
PROMPT &cab1
PROMPT &cab2
SET TERMOUT OFF
SET SQLFORMAT DEFAULT
SET TERMOUT ON
SET LINESIZE 160 PAGESIZE 100 FEEDBACK OFF
COLUMN archivo FORMAT A20
COLUMN donde FORMAT A62
COLUMN proteccion FORMAT A44
COLUMN member FORMAT A44
PROMPT == 1. Control files (Lab 5, Parte J: tres copias) ==
SELECT 'control file' AS archivo, name AS donde, status FROM v$controlfile;
PROMPT == 2. Redo en línea: grupos y miembros (Lab 5, Parte K: dos miembros por grupo) ==
SELECT l.group#, l.sequence#, ROUND(l.bytes / 1048576) AS mb, l.members, l.status, l.archived, f.member
  FROM v$log l JOIN v$logfile f ON f.group# = l.group# ORDER BY l.group#, f.member;
PROMPT == 3. SPFILE, password file y redo archivado ==
SELECT 'spfile' AS archivo, value AS donde FROM v$parameter WHERE name = 'spfile'
UNION ALL SELECT 'password file', file_name FROM v$passwordfile_info
UNION ALL SELECT 'FRA', name || ' (' || ROUND(space_used / 1048576) || ' de ' || ROUND(space_limit / 1048576) || ' MB)' FROM v$recovery_file_dest;
SELECT log_mode, (SELECT COUNT(*) FROM v$archived_log WHERE name IS NOT NULL) AS archivados_en_disco FROM v$database;
PROMPT == 4. ¿Hay copia RMAN reciente? (la del simulacro D del Lab 5) ==
SELECT TO_CHAR(MAX(completion_time), 'YYYY-MM-DD HH24:MI') AS ultima_pieza_rman, COUNT(*) AS piezas FROM v$backup_piece WHERE status = 'A';
PROMPT == 5. ¿Quién puede conectarse como SYS* por el password file? ==
COLUMN username FORMAT A12
SELECT username, sysdba, sysoper, sysbackup, sysdg, syskm, account_status FROM v$pwfile_users;
SPOOL OFF
