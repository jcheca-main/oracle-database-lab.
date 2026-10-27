-- scripts/lab5/05-reto-revision.sql
-- Reto profesional de la Parte F: revision de codigo de un PR.
-- Consulta del compa~ero: SELECT * FROM tiendasur.cliente WHERE SUBSTR(telefono,1,3)='600' OR UPPER(apellidos)='GIL'
-- Rompe la regla 1 (funcion SUBSTR y UPPER sobre la columna) y la regla 5 (OR cuyas dos ramas son no indexables).
WHENEVER SQLERROR EXIT FAILURE
ALTER SESSION SET CONTAINER = FREEPDB1;
SET SERVEROUTPUT ON FORMAT WRAPPED LINESIZE 200
-- recrear los indices temporales que la Parte F borra
CREATE INDEX tiendasur.ix_cli_telefono ON tiendasur.cliente (telefono);
CREATE INDEX tiendasur.ix_cli_apellidos ON tiendasur.cliente (apellidos);
PROMPT === ANTES (rota): funciones sobre la columna + OR ===
EXEC lab_tools.medir.consulta('PR rota', q'[SELECT * FROM tiendasur.cliente WHERE SUBSTR(telefono,1,3)='600' OR UPPER(apellidos)='GIL' ]')
PROMPT === DESPUES (reescribir): rango de prefijo en telefono + columna desnuda en apellidos ===
EXEC lab_tools.medir.consulta('PR reescrita', q'[SELECT * FROM tiendasur.cliente WHERE (telefono >= '600' AND telefono < '601') OR apellidos = 'Gil' ]')
PROMPT === nota: apellidos guarda DOS palabras ('Gonzalez Gil'); UPPER(apellidos)='GIL' no casa con nada ===
SELECT COUNT(*) AS filas_apellidos_Gil FROM tiendasur.cliente WHERE apellidos = 'Gil';
SELECT COUNT(*) AS filas_telefono_600 FROM tiendasur.cliente WHERE telefono >= '600' AND telefono < '601';
PROMPT === limpieza ===
DROP INDEX tiendasur.ix_cli_telefono;
DROP INDEX tiendasur.ix_cli_apellidos;
SELECT COUNT(*) AS indices_tiendasur FROM dba_indexes WHERE owner='TIENDASUR';
EXIT
