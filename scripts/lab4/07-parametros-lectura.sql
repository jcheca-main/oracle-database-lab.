-- scripts/lab4/07-parametros-lectura.sql — de dónde sale cada parámetro y qué se puede cambiar (SQLcl · C##OPS_RO)
@scripts/ops/marca
SPOOL docs/bitacora/lab4/evidencia/spool/&marca._07-parametros-lectura.spool.log
SET SQLFORMAT DEFAULT
SET LINESIZE 180 PAGESIZE 100 FEEDBACK OFF
COLUMN name FORMAT A30
COLUMN value FORMAT A58
COLUMN display_value FORMAT A14
COLUMN sid FORMAT A4
PROMPT
PROMPT == 1. ¿Arrancó con SPFILE o con PFILE? (valor vacío = PFILE) ==
SELECT name, value FROM v$parameter WHERE name = 'spfile';
PROMPT
PROMPT == 2. Parámetros que marcan la arquitectura del curso (valor efectivo en esta instancia) ==
SELECT name, display_value, isdefault, ismodified,
       issys_modifiable AS sys_mod, isses_modifiable AS ses_mod, ispdb_modifiable AS pdb_mod
  FROM v$parameter
 WHERE name IN ('db_name', 'db_block_size', 'compatible', 'cpu_count',
                'memory_size', 'sga_target', 'pga_aggregate_target', 'pga_aggregate_limit',
                'processes', 'sessions', 'open_cursors', 'db_files',
                'undo_tablespace', 'undo_retention', 'db_create_file_dest',
                'db_recovery_file_dest', 'db_recovery_file_dest_size',
                'vector_memory_size', 'inmemory_size', 'enable_pluggable_database')
 ORDER BY name;
PROMPT
PROMPT == 3. Lo que está escrito en el SPFILE (v$spparameter: solo los especificados) ==
SELECT sid, name, value FROM v$spparameter WHERE isspecified = 'TRUE' AND name NOT LIKE '\_%' ESCAPE '\' ORDER BY name;
PROMPT
PROMPT == 4. Recuento: cuántos parámetros hay y cuántos no están en su valor por defecto ==
SELECT COUNT(*) AS documentados,
       SUM(CASE WHEN isdefault = 'FALSE' THEN 1 ELSE 0 END) AS no_por_defecto,
       SUM(CASE WHEN issys_modifiable = 'FALSE' THEN 1 ELSE 0 END) AS estaticos
  FROM v$parameter;
SPOOL OFF
