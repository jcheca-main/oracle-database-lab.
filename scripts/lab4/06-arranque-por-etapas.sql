-- scripts/lab4/06-arranque-por-etapas.sql — parada y arranque etapa a etapa (SHUTDOWN → NOMOUNT → MOUNT → OPEN)
-- Se ejecuta como SYSDBA con autenticación del SO: bash scripts/ops/sysdba.sh <este archivo> <evidencia>
-- Los errores ORA-01507 y ORA-01219 son ESPERADOS: demuestran qué existe en cada etapa.
WHENEVER SQLERROR CONTINUE
SET LINESIZE 160 PAGESIZE 100 FEEDBACK OFF ECHO OFF
COLUMN instance_name FORMAT A10
COLUMN name FORMAT A40
COLUMN value FORMAT A70
PROMPT
PROMPT ===== 0. Punto de partida =====
SELECT instance_name, status, database_status FROM v$instance;
PROMPT
PROMPT ===== 1. SHUTDOWN IMMEDIATE: checkpoint, cierre de archivos, fin de procesos =====
SHUTDOWN IMMEDIATE
PROMPT
PROMPT ===== 2. STARTUP NOMOUNT: lee el SPFILE, reserva la SGA y arranca los procesos =====
STARTUP NOMOUNT
SELECT instance_name, status FROM v$instance;
PROMPT -- v$parameter ya responde (sale del SPFILE en memoria):
SELECT name, value FROM v$parameter WHERE name IN ('control_files', 'db_name', 'spfile');
PROMPT -- v$database todavía NO (no se ha leído el control file) -> ORA-01507 esperado:
SELECT name, open_mode FROM v$database;
PROMPT
PROMPT ===== 3. ALTER DATABASE MOUNT: abre los control files y conoce la estructura =====
ALTER DATABASE MOUNT;
SELECT instance_name, status FROM v$instance;
SELECT name, open_mode, log_mode FROM v$database;
SELECT name FROM v$controlfile;
SELECT COUNT(*) AS datafiles_conocidos FROM v$datafile;
PROMPT -- El diccionario (tablas de SYSTEM) todavía NO es accesible -> ORA-01219 esperado:
SELECT COUNT(*) FROM dba_tables;
PROMPT
PROMPT ===== 4. ALTER DATABASE OPEN: abre datafiles y redo; recuperación de instancia si hiciera falta =====
ALTER DATABASE OPEN;
SELECT instance_name, status, database_status FROM v$instance;
SELECT name, open_mode FROM v$database;
PROMPT -- Las PDB: el estado guardado (SAVE STATE) decide si FREEPDB1 se abre sola
SELECT con_id, name, open_mode, restricted FROM v$pdbs ORDER BY con_id;
COLUMN con_name FORMAT A12
COLUMN instance_name FORMAT A12
COLUMN state FORMAT A8
SELECT con_name, instance_name, state FROM dba_pdb_saved_states;
PROMPT -- Si FREEPDB1 se quedó en MOUNTED (no había estado guardado), se abre y se guarda el estado para el próximo arranque
SET SERVEROUTPUT ON
DECLARE v VARCHAR2(10);
BEGIN
  SELECT open_mode INTO v FROM v$pdbs WHERE name = 'FREEPDB1';
  IF v <> 'READ WRITE' THEN
    EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE FREEPDB1 OPEN';
    EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE FREEPDB1 SAVE STATE';
    DBMS_OUTPUT.PUT_LINE('FREEPDB1 estaba ' || v || ': abierta y con SAVE STATE (repasa por qué no tenía estado guardado)');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FREEPDB1 abierta sola en READ WRITE: el estado guardado funciona');
  END IF;
END;
/
PROMPT
PROMPT ===== 5. ¿Dónde quedó escrito todo esto? (ADR y alert log) =====
SELECT name, value FROM v$diag_info WHERE name IN ('ADR Home', 'Diag Trace', 'Default Trace File');
EXIT
