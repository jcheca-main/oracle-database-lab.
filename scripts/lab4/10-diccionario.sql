-- scripts/lab4/10-diccionario.sql — diccionario de datos frente a vistas dinámicas (SQLcl · C##OPS_RO · servicio FREE)
@scripts/ops/marca
SPOOL docs/bitacora/lab4/evidencia/spool/&marca._10-diccionario.spool.log
SET SQLFORMAT DEFAULT
SET LINESIZE 160 PAGESIZE 100 FEEDBACK OFF
COLUMN familia FORMAT A42
COLUMN contenedor FORMAT A10
COLUMN tablespace_name FORMAT A14
PROMPT
PROMPT == 1. Familias de vistas: quién ve qué ==
SELECT 'USER_  (lo mío)' AS familia, COUNT(*) AS vistas FROM dba_views WHERE owner = 'SYS' AND view_name LIKE 'USER\_%' ESCAPE '\'
UNION ALL SELECT 'ALL_   (aquello a lo que tengo acceso)', COUNT(*) FROM dba_views WHERE owner = 'SYS' AND view_name LIKE 'ALL\_%' ESCAPE '\'
UNION ALL SELECT 'DBA_   (todo el contenedor actual)', COUNT(*) FROM dba_views WHERE owner = 'SYS' AND view_name LIKE 'DBA\_%' ESCAPE '\'
UNION ALL SELECT 'CDB_   (todos los contenedores)', COUNT(*) FROM dba_views WHERE owner = 'SYS' AND view_name LIKE 'CDB\_%' ESCAPE '\'
UNION ALL SELECT 'V$     (dinámicas: memoria y control file)', COUNT(*) FROM v$fixed_table WHERE type = 'VIEW' AND name LIKE 'V$%'
UNION ALL SELECT 'GV$    (V$ de todas las instancias, RAC)', COUNT(*) FROM v$fixed_table WHERE type = 'VIEW' AND name LIKE 'GV$%';
PROMPT
PROMPT == 2. La misma pregunta con DBA_ y con CDB_: ¿cuántos tablespaces hay? ==
SELECT 'DBA_TABLESPACES (solo CDB$ROOT)' AS familia, COUNT(*) AS n FROM dba_tablespaces
UNION ALL SELECT 'CDB_TABLESPACES (todos los abiertos)', COUNT(*) FROM cdb_tablespaces;
SELECT c.name AS contenedor, COUNT(*) AS tablespaces
  FROM cdb_tablespaces t JOIN v$containers c ON c.con_id = t.con_id GROUP BY c.name ORDER BY c.name;
PROMPT
PROMPT == 3. Las V$ se apoyan en tablas X$ en memoria (v$fixed_table) ==
SELECT type, COUNT(*) AS n FROM v$fixed_table GROUP BY type ORDER BY type;
PROMPT
PROMPT == 4. Una vista se describe a sí misma: definición de V$LOG (v$fixed_view_definition) ==
COLUMN view_definition FORMAT A140 WORD_WRAPPED
SELECT view_definition FROM v$fixed_view_definition WHERE view_name = 'GV$LOG';
SPOOL OFF
