-- scripts/lab6/02-parametros.sql — de dónde nace la instancia y dónde queda un cambio (Unidad 5, 5.2.3)
-- SYSDBA:  bash scripts/ops/sysdba.sh scripts/lab6/02-parametros.sql "$EVID_LAB6/script/$(ts)_02-parametros.script.log"
-- Deja dos copias de texto de los parámetros en /opt/oracle/oradata/lab6/ (dentro del volumen: sobreviven al contenedor).
SET LINESIZE 160 PAGESIZE 100 FEEDBACK ON 
COLUMN name FORMAT A22
COLUMN value FORMAT A44
COLUMN issys_modifiable FORMAT A16
COLUMN ispdb_modifiable FORMAT A16
COLUMN isspecified FORMAT A11
COLUMN origen FORMAT A17
PROMPT == 1. ¿Con qué archivo de parámetros arrancó la instancia? ==
SELECT name, value FROM v$parameter WHERE name = 'spfile';
PROMPT == 2. Red de seguridad antes de tocar nada: el último estado bueno, en texto ==
CREATE PFILE = '/opt/oracle/oradata/lab6/init_desde_spfile.ora' FROM SPFILE;
CREATE PFILE = '/opt/oracle/oradata/lab6/init_desde_memoria.ora' FROM MEMORY;
PROMPT == 3. Tipos de parámetro: estático (FALSE), dinámico inmediato, dinámico diferido; y si la PDB puede tener el suyo ==
SELECT name, value, issys_modifiable, ispdb_modifiable FROM v$parameter
 WHERE name IN ('db_files', 'db_recovery_file_dest_size', 'undo_retention', 'sort_area_size', 'control_files', 'resumable_timeout')
 ORDER BY issys_modifiable, name;
PROMPT == 4. Un parámetro ESTÁTICO no se puede cambiar en memoria (error esperado: ORA-02095) ==
ALTER SYSTEM SET db_files = 250 SCOPE = MEMORY;
PROMPT == 5. Con SCOPE = SPFILE se acepta... pero solo vale en el próximo arranque ==
SELECT 'SPFILE (antes)' AS origen, NVL(value, '(sin fijar)') AS value, isspecified FROM v$spparameter WHERE name = 'db_files';
ALTER SYSTEM SET db_files = 250 COMMENT = 'Lab 6: prueba de SCOPE, se deshace en el paso 6' SCOPE = SPFILE;
SELECT 'SPFILE (archivo)' AS origen, value, isspecified FROM v$spparameter WHERE name = 'db_files'
UNION ALL
SELECT 'MEMORIA (en uso)', value, NULL FROM v$parameter WHERE name = 'db_files';
PROMPT == 6. Vuelta atrás. db_files NO estaba fijado (la copia del paso 2 no lo tiene): se deshace con RESET ==
ALTER SYSTEM RESET db_files SCOPE = SPFILE;
SELECT 'SPFILE (después)' AS origen, NVL(value, '(sin fijar)') AS value, isspecified FROM v$spparameter WHERE name = 'db_files';
PROMPT == 7. Desde una PDB no se cambia un parámetro del CDB (error esperado: ORA-65040) ==
ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER SYSTEM SET processes = 250 SCOPE = SPFILE;
ALTER SESSION SET CONTAINER = CDB$ROOT;
EXIT
