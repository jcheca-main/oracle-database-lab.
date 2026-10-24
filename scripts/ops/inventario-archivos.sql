-- scripts/ops/inventario-archivos.sql — qué archivos forman HOY la base de datos (todas las PDB)
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 400 TRIMOUT ON VERIFY OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE
SELECT 'META|version|' || version_full FROM v$instance;
SELECT 'META|base|' || name || '|log_mode=' || log_mode || '|scn=' || TO_CHAR(current_scn) FROM v$database;
SELECT 'FILE|datafile|' || name   FROM v$datafile;
SELECT 'FILE|tempfile|' || name   FROM v$tempfile;
SELECT 'FILE|redo|'     || member FROM v$logfile;
SELECT 'FILE|control|'  || name   FROM v$controlfile;
SELECT 'FILE|spfile|'   || value  FROM v$parameter WHERE name = 'spfile' AND value IS NOT NULL;
SELECT 'FILE|pwfile|'   || file_name FROM v$passwordfile_info WHERE file_name IS NOT NULL;
EXIT
