-- scripts/lab5/06-reto-v006.sql
-- Reto profesional de la Parte G: proponer V006 para una consulta que V005 NO cubre y pasarla por las 5 preguntas.
-- Consulta elegida: Q4b (buscar por apellidos LIKE 'Gonz%'). Propuesta: ix_cli_apellidos.
WHENEVER SQLERROR EXIT FAILURE
ALTER SESSION SET CONTAINER = FREEPDB1;
SET SERVEROUTPUT ON FORMAT WRAPPED LINESIZE 200
PROMPT === Pregunta 1/2 · VIABILIDAD: selectividad de 'Gonz%' (~2.1%) y lecturas base SIN indice ===
EXEC lab_tools.medir.consulta('Q4b sin indice (hoy)', q'[SELECT id_cliente, nombre, apellidos FROM tiendasur.cliente WHERE apellidos LIKE 'Gonz%' ]')
PROMPT === proponer V006: ix_cli_apellidos (ONLINE) ===
CREATE INDEX tiendasur.ix_cli_apellidos ON tiendasur.cliente (apellidos);
EXEC lab_tools.medir.consulta('Q4b con ix_cli_apellidos', q'[SELECT id_cliente, nombre, apellidos FROM tiendasur.cliente WHERE apellidos LIKE 'Gonz%' ]')
PROMPT === el CF decide: indice propuesto vs bloques de la tabla ===
SELECT i.index_name, i.clustering_factor, t.blocks AS bloques_tabla, i.num_rows
FROM dba_indexes i JOIN dba_tables t ON t.owner=i.owner AND t.table_name=i.table_name
WHERE i.owner='TIENDASUR' AND i.index_name='IX_CLI_APELLIDOS';
PROMPT === Pregunta 3 · ESCRITURA: bloques/redo por INSERT con el indice (se deshace) ===
EXEC lab_tools.medir.dml('INSERT 1 fila con ix_cli_apellidos', 'INSERT INTO tiendasur.cliente (id_cliente,dni,email,nombre,apellidos,telefono,pais,ciudad,fecha_alta) VALUES (999991, ''99999999Z'', ''v6@tiendasur.es'', ''V6'', ''Gonzalez Gil'', ''699999999'', ''ES'', ''Lorca'', SYSDATE)')
PROMPT === Pregunta 4 · REDUNDANCIA: ¿otro indice cubre apellidos por prefijo? ===
SELECT COUNT(*) AS otros_idx_apellidos FROM dba_indexes WHERE owner='TIENDASUR' AND index_name LIKE '%PELLID%';
PROMPT === limpieza: V006 NO se fusiona (conclusion: no compensa) ===
DROP INDEX tiendasur.ix_cli_apellidos;
SELECT COUNT(*) AS indices_tiendasur FROM dba_indexes WHERE owner='TIENDASUR';
EXIT
