-- scripts/lab4/10-ciclo-vida-pdb.sql — CDB, root, seed y PDB; usuarios comunes y locales; ciclo de vida de una PDB
-- Se ejecuta como SYSDBA: bash scripts/ops/sysdba.sh <este archivo> <evidencia>
-- Deja todo como estaba: la PDB y el usuario local de prueba se borran al final.
WHENEVER SQLERROR CONTINUE
SET LINESIZE 160 PAGESIZE 100 FEEDBACK OFF SERVEROUTPUT ON
COLUMN name FORMAT A12
COLUMN pdb_name FORMAT A12
COLUMN username FORMAT A16
COLUMN contenedor FORMAT A10
COLUMN network_name FORMAT A12
COLUMN common_user_prefix FORMAT A20
PROMPT
PROMPT ===== 1. Los contenedores de la CDB =====
SELECT con_id, name, open_mode, restricted, ROUND(total_size / 1048576) AS mb FROM v$containers ORDER BY con_id;
PROMPT
PROMPT ===== 2. Usuarios: comunes (C##, existen en todos los contenedores) frente a locales =====
SELECT u.username, u.common, c.name AS contenedor
  FROM cdb_users u JOIN v$containers c ON c.con_id = u.con_id
 WHERE u.username IN ('SYS', 'SYSTEM', 'C##OPS_RO', 'PDBADMIN', 'ADMIN_ACADEMIA') ORDER BY u.username, c.con_id;
PROMPT
PROMPT ===== 3. Errores de examen al crear usuarios =====
PROMPT -- El prefijo obligatorio de los usuarios comunes (por defecto C##):
SELECT NVL(value, '(vacío)') AS common_user_prefix FROM v$parameter WHERE name = 'common_user_prefix';
PROMPT -- 3a. Usuario sin el prefijo en la raíz (ORA-65096 esperado si el prefijo es C##)
CREATE USER lab4_local NO AUTHENTICATION;
PROMPT -- (si la imagen dejó el prefijo vacío, el usuario se habrá creado como COMÚN: lo borramos)
BEGIN EXECUTE IMMEDIATE 'DROP USER lab4_local'; DBMS_OUTPUT.PUT_LINE('Se creó como común y se ha borrado'); EXCEPTION WHEN OTHERS THEN NULL; END;
/
ALTER SESSION SET CONTAINER = FREEPDB1;
PROMPT -- 3b. Usuario común (C##) desde una PDB (ORA-65094 esperado)
CREATE USER c##lab4_comun NO AUTHENTICATION;
PROMPT -- 3c. Usuario local en la PDB: correcto
CREATE USER lab4_local NO AUTHENTICATION;
SELECT username, common, SYS_CONTEXT('USERENV', 'CON_NAME') AS contenedor FROM dba_users WHERE username = 'LAB4_LOCAL';
DROP USER lab4_local;
ALTER SESSION SET CONTAINER = CDB$ROOT;
PROMPT
PROMPT ===== 4. Ciclo de vida: crear una PDB desde la semilla (PDB$SEED) =====
PROMPT (la contraseña del administrador se genera al azar y no se muestra: nadie va a iniciar sesión con él)
DECLARE
  v_pwd VARCHAR2(30) := 'L4_' || DBMS_RANDOM.STRING('A', 12) || '_' || TRUNC(DBMS_RANDOM.VALUE(10, 99));
BEGIN
  EXECUTE IMMEDIATE 'CREATE PLUGGABLE DATABASE pdb_lab4 ADMIN USER pdb_lab4_admin IDENTIFIED BY "' || v_pwd || '"'
    || ' FILE_NAME_CONVERT = (''/opt/oracle/oradata/FREE/pdbseed/'', ''/opt/oracle/oradata/FREE/PDB_LAB4/'')';
  DBMS_OUTPUT.PUT_LINE('PDB_LAB4 creada');
END;
/
SELECT con_id, name, open_mode FROM v$pdbs ORDER BY con_id;
ALTER PLUGGABLE DATABASE pdb_lab4 OPEN;
SELECT con_id, name, open_mode FROM v$pdbs ORDER BY con_id;
PROMPT -- Sus archivos (copiados de la semilla) y su servicio, que LREG registra en el listener
SELECT file_name FROM cdb_data_files WHERE con_id = (SELECT con_id FROM v$pdbs WHERE name = 'PDB_LAB4');
SELECT name, network_name FROM v$services WHERE con_id = (SELECT con_id FROM v$pdbs WHERE name = 'PDB_LAB4');
PROMPT
PROMPT ===== 5. Borrar la PDB: primero cerrarla (ORA-65025 si está abierta), después DROP con sus archivos =====
DROP PLUGGABLE DATABASE pdb_lab4 INCLUDING DATAFILES;
ALTER PLUGGABLE DATABASE pdb_lab4 CLOSE IMMEDIATE;
DROP PLUGGABLE DATABASE pdb_lab4 INCLUDING DATAFILES;
PROMPT (queda la carpeta PDB_LAB4 vacía; 10-ciclo-vida-pdb.sh la elimina)
SELECT con_id, name, open_mode FROM v$pdbs ORDER BY con_id;
EXIT
