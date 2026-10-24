-- scripts/lab4/11-archivos.sql — autopsia de los archivos: cada tipo, dónde está, cuánto ocupa y si es parte de la base
-- SQLcl · C##OPS_RO · servicio FREE (la raíz ve los archivos de todos los contenedores)
@scripts/ops/marca
SPOOL docs/bitacora/lab4/evidencia/spool/&marca._11-archivos.spool.log
SET SQLFORMAT DEFAULT
SET LINESIZE 170 PAGESIZE 100 FEEDBACK OFF
COLUMN tipo FORMAT A26
COLUMN ruta FORMAT A58
COLUMN contenedor FORMAT A10
COLUMN parte_de_la_base FORMAT A16
COLUMN name FORMAT A28
COLUMN value FORMAT A58
COLUMN estado FORMAT A8
COLUMN message_text FORMAT A80 TRUNCATED
PROMPT
PROMPT == 1. Los archivos que SON la base de datos: datafiles, tempfiles, control files y redo online ==
SELECT 'datafile' AS tipo, c.name AS contenedor, f.name AS ruta, ROUND(f.bytes / 1048576) AS mb, f.status AS estado
  FROM v$datafile f JOIN v$containers c ON c.con_id = f.con_id
UNION ALL
SELECT 'tempfile', c.name, t.name, ROUND(t.bytes / 1048576), t.status
  FROM v$tempfile t JOIN v$containers c ON c.con_id = t.con_id
UNION ALL
SELECT 'control file', 'CDB', name, ROUND(block_size * file_size_blks / 1048576), NVL(status, 'OK') FROM v$controlfile
UNION ALL
SELECT 'redo online (grupo ' || l.group# || ')', 'CDB', f.member, ROUND(l.bytes / 1048576), l.status
  FROM v$log l JOIN v$logfile f ON f.group# = l.group#
ORDER BY 1, 2, 3;
PROMPT
PROMPT == 2. Resumen por tipo ==
SELECT tipo, COUNT(*) AS archivos, ROUND(SUM(mb)) AS mb, parte_de_la_base FROM (
  SELECT 'datafile' AS tipo, bytes / 1048576 AS mb, 'SÍ' AS parte_de_la_base FROM v$datafile
  UNION ALL SELECT 'tempfile', bytes / 1048576, 'SÍ (no se copia)' FROM v$tempfile
  UNION ALL SELECT 'control file', block_size * file_size_blks / 1048576, 'SÍ' FROM v$controlfile
  UNION ALL SELECT 'redo online', l.bytes / 1048576, 'SÍ' FROM v$log l JOIN v$logfile f ON f.group# = l.group#
  UNION ALL SELECT 'redo archivado', blocks * block_size / 1048576, 'no (relacionado)' FROM v$archived_log WHERE name IS NOT NULL)
 GROUP BY tipo, parte_de_la_base ORDER BY parte_de_la_base DESC, tipo;
PROMPT
PROMPT == 3. Los archivos RELACIONADOS (imprescindibles, pero no son la base): SPFILE, password file, ADR ==
SELECT 'SPFILE' AS name, value FROM v$parameter WHERE name = 'spfile'
UNION ALL SELECT 'password file', file_name FROM v$passwordfile_info
UNION ALL SELECT 'formato password file', format FROM v$passwordfile_info
UNION ALL SELECT 'diagnostic_dest (ADR)', value FROM v$parameter WHERE name = 'diagnostic_dest'
UNION ALL SELECT name, value FROM v$diag_info WHERE name IN ('Diag Alert', 'Diag Trace')
UNION ALL SELECT 'FRA (db_recovery_file_dest)', NVL(value, '(sin configurar: llegará en el Lab 5)') FROM v$parameter WHERE name = 'db_recovery_file_dest'
UNION ALL SELECT 'modo de archivado', log_mode FROM v$database;
PROMPT
PROMPT == 4. Quién puede entrar como SYSDBA desde fuera (el password file por dentro: v$pwfile_users) ==
COLUMN username FORMAT A12
SELECT username, sysdba, sysoper, sysbackup, account_status FROM v$pwfile_users;
PROMPT
PROMPT == 5. El alert log leído con SQL: últimas 8 líneas (v$diag_alert_ext) ==
SELECT TO_CHAR(originating_timestamp, 'MM-DD HH24:MI:SS') AS cuando, REPLACE(message_text, CHR(10), ' ') AS message_text
  FROM v$diag_alert_ext WHERE con_id IN (0, 1)
 ORDER BY originating_timestamp DESC FETCH FIRST 8 ROWS ONLY;
PROMPT
PROMPT == 6. TEMP: el único tablespace cuyos archivos no se respaldan (se recrean) ==
COLUMN tablespace_name FORMAT A12
SELECT con_id, tablespace_name, contents, bigfile FROM cdb_tablespaces WHERE contents = 'TEMPORARY' ORDER BY con_id;
SPOOL OFF
