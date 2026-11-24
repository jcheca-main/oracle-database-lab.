-- scripts/lab6/04-diccionario.sql — de dónde salen las vistas y cómo encontrar la que no conoces (Unidad 5, 5.4.2 y 5.4.7)
-- Solo lectura:  bash scripts/ops/ro.sh scripts/lab6/04-diccionario.sql
@scripts/ops/marca
@scripts/ops/cabecera 04-diccionario
SPOOL docs/bitacora/lab6/evidencia/spool/&marca._04-diccionario.spool.log
PROMPT &cab1
PROMPT &cab2
SET TERMOUT OFF
SET SQLFORMAT DEFAULT
SET TERMOUT ON
SET LINESIZE 160 PAGESIZE 100 FEEDBACK OFF LONG 400
COLUMN view_definition FORMAT A120 WORD_WRAPPED
COLUMN owner FORMAT A8
COLUMN synonym_name FORMAT A14
COLUMN table_owner FORMAT A8
COLUMN table_name FORMAT A30
COLUMN comments FORMAT A80 WORD_WRAPPED
COLUMN column_name FORMAT A16
COLUMN username FORMAT A10
COLUMN default_attr FORMAT A12
COLUMN object_name FORMAT A12
COLUMN all_containers FORMAT A14
PROMPT == 1. Las tablas fijas X$ y las vistas V$ y GV$ que se apoyan en ellas (exponen estructuras de memoria de la instancia y datos del control file) ==
SELECT COUNT(*) AS total, SUM(CASE WHEN name LIKE 'X$%' THEN 1 ELSE 0 END) AS x_tablas,
       SUM(CASE WHEN name LIKE 'V$%' THEN 1 ELSE 0 END) AS v_vistas,
       SUM(CASE WHEN name LIKE 'GV$%' THEN 1 ELSE 0 END) AS gv_vistas
  FROM v$fixed_table;
PROMPT == 2. V$INSTANCE es GV$INSTANCE filtrada a ESTA instancia ==
SELECT view_definition FROM v$fixed_view_definition WHERE view_name = 'V$INSTANCE';
PROMPT == 3. Lo que escribes (V$SESSION, DBA_USERS) son sinónimos públicos ==
SELECT owner, synonym_name, table_owner, table_name FROM dba_synonyms
 WHERE owner = 'PUBLIC' AND synonym_name IN ('V$SESSION', 'DBA_USERS');
PROMPT == 4. ¿Qué vista me dice las cuotas? Primera trampa: DICTIONARY solo lista lo concedido a PUBLIC o a ti ==
SELECT COUNT(*) AS vistas_dba_en_dictionary FROM dictionary WHERE table_name LIKE 'DBA%';
PROMPT -- Con SELECT_CATALOG_ROLE se pregunta a los comentarios del catálogo (DBA_TAB_COMMENTS):
SELECT table_name, comments FROM dba_tab_comments
 WHERE owner = 'SYS' AND (table_name LIKE 'DBA%QUOTA%' OR table_name LIKE 'DBA%RESUMABLE%') ORDER BY table_name;
PROMPT == 5. ¿Y qué columnas tiene? (DBA_COL_COMMENTS; MAX_BYTES = -1 significa ilimitada) ==
SELECT column_name, comments FROM dba_col_comments WHERE owner = 'SYS' AND table_name = 'DBA_TS_QUOTAS' ORDER BY column_name;
PROMPT == 6. ¿A qué contenedores puede mirar C##OPS_RO? (CONTAINER_DATA) ==
SELECT username, default_attr, owner, object_name, all_containers FROM cdb_container_data WHERE username = 'C##OPS_RO';
SPOOL OFF
