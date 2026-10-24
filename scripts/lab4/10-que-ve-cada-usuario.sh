#!/usr/bin/env bash
# scripts/lab4/10-que-ve-cada-usuario.sh — navegar por contenedores: qué ve cada usuario, desde dónde y por qué
# Crea dos usuarios de prueba con una contraseña aleatoria que nadie conoce (viaja por la entrada estándar, no se guarda),
# se conecta como cada uno, compara lo que ven y los borra al final. Uso:
#   bash scripts/lab4/10-que-ve-cada-usuario.sh | tee "$EVID_LAB4/script/$(ts)_10-que-ve-cada-usuario.script.log"
set -euo pipefail
source scripts/deployment/env/00-config.sh
PWD_PRUEBA="L4_$(head -c 48 /dev/urandom | base64 | tr -dc "A-Za-z0-9" | cut -c1-14)_9"
docker exec -i "$CONT_NAME" sqlplus -s -L / as sysdba <<SQL
SET LINESIZE 150 PAGESIZE 100 FEEDBACK OFF VERIFY OFF
COLUMN quien FORMAT A44
COLUMN con_name FORMAT A10
COLUMN con_id_actual FORMAT A13
COLUMN username FORMAT A16
COLUMN default_attr FORMAT A12
COLUMN all_containers FORMAT A14
COLUMN contenedor FORMAT A10
COLUMN owner FORMAT A16
COLUMN table_name FORMAT A18
COLUMN prueba FORMAT A46
COLUMN resultado FORMAT A60
WHENEVER SQLERROR CONTINUE
PROMPT
PROMPT ===== 0. Preparación (como SYSDBA): un usuario LOCAL en FREEPDB1 y uno COMÚN sin CONTAINER_DATA =====
ALTER SESSION SET CONTAINER = FREEPDB1;
DROP USER IF EXISTS lab4_analista CASCADE;
CREATE USER lab4_analista IDENTIFIED BY "$PWD_PRUEBA";
GRANT CREATE SESSION TO lab4_analista;
ALTER SESSION SET CONTAINER = CDB\$ROOT;
DROP USER IF EXISTS c##lab4_auditor CASCADE;
CREATE USER c##lab4_auditor IDENTIFIED BY "$PWD_PRUEBA" CONTAINER = ALL;
GRANT CREATE SESSION, SET CONTAINER, SELECT_CATALOG_ROLE TO c##lab4_auditor CONTAINER = ALL;
PROMPT Usuarios de prueba creados (contraseña aleatoria, no se muestra ni se guarda)
PROMPT
PROMPT ===== 1. SYS en la raíz: ¿dónde estoy y qué ve V\$? =====
SELECT SYS_CONTEXT('USERENV', 'CON_NAME') AS con_name, SYS_CONTEXT('USERENV', 'CON_ID') AS con_id_actual FROM dual;
SELECT con_id, COUNT(*) AS datafiles FROM v\$datafile GROUP BY con_id ORDER BY con_id;
PROMPT (CON_ID 1 = CDB\$ROOT, 2 = PDB\$SEED, 3 = FREEPDB1; 0 = dato de toda la CDB, sin contenedor concreto)
SELECT con_id, COUNT(*) AS filas_en_v_log FROM v\$log GROUP BY con_id;
PROMPT
PROMPT ===== 2. SYS dentro de FREEPDB1: las mismas vistas, otra respuesta =====
ALTER SESSION SET CONTAINER = FREEPDB1;
SELECT SYS_CONTEXT('USERENV', 'CON_NAME') AS con_name, SYS_CONTEXT('USERENV', 'CON_ID') AS con_id_actual FROM dual;
SELECT con_id, COUNT(*) AS datafiles FROM v\$datafile GROUP BY con_id ORDER BY con_id;
SELECT COUNT(*) AS tablespaces_dba FROM dba_tablespaces;
SELECT con_id, COUNT(*) AS tablespaces_cdb FROM cdb_tablespaces GROUP BY con_id;
PROMPT (dentro de una PDB, CDB_ = DBA_: solo se ve la propia PDB)
PROMPT
PROMPT ===== 3. Usuario LOCAL con solo CREATE SESSION (lab4_analista @ freepdb1) =====
CONNECT lab4_analista/"$PWD_PRUEBA"@//localhost:1521/freepdb1
SELECT SYS_CONTEXT('USERENV', 'SESSION_USER') AS quien, SYS_CONTEXT('USERENV', 'CON_NAME') AS con_name FROM dual;
SELECT 'USER_TABLES (lo mío)' AS prueba, COUNT(*) AS filas FROM user_tables
UNION ALL SELECT 'ALL_TABLES de ADMIN_ACADEMIA (lo accesible)', COUNT(*) FROM all_tables WHERE owner = 'ADMIN_ACADEMIA';
PROMPT -- 3a. DBA_TABLES y V\$SESSION: ORA-00942 esperado (no "sin privilegios": Oracle no revela lo que no puedes ver)
SELECT COUNT(*) FROM dba_tables;
SELECT COUNT(*) FROM v\$session;
PROMPT -- 3b. Leer una tabla de negocio: ORA-00942 esperado
SELECT COUNT(*) FROM admin_academia.aca_estudiantes;
PROMPT -- 3c. Saltar a la raíz: ORA-01031 esperado (no tiene SET CONTAINER y además no existe en la raíz)
ALTER SESSION SET CONTAINER = CDB\$ROOT;
PROMPT
PROMPT ===== 4. Privilegio de ESQUEMA (novedad de 23ai): leer TODO ADMIN_ACADEMIA y nada más =====
CONNECT / AS SYSDBA
ALTER SESSION SET CONTAINER = FREEPDB1;
GRANT READ ANY TABLE ON SCHEMA admin_academia TO lab4_analista;
CONNECT lab4_analista/"$PWD_PRUEBA"@//localhost:1521/freepdb1
SELECT owner, table_name FROM all_tables WHERE owner = 'ADMIN_ACADEMIA' ORDER BY table_name;
SELECT COUNT(*) AS estudiantes FROM admin_academia.aca_estudiantes;
PROMPT -- 4a. Otro esquema sigue cerrado: ORA-00942 esperado
SELECT COUNT(*) FROM admin_clinica.cli_pacientes;
PROMPT -- 4b. Leer no es escribir: ORA-41900 esperado (23ai: el mensaje dice exactamente qué privilegio falta)
UPDATE admin_academia.aca_estudiantes SET estado = estado WHERE estudiante_id = 101;
PROMPT
PROMPT ===== 5. Usuario COMÚN sin CONTAINER_DATA (c##lab4_auditor) frente a C##OPS_RO =====
CONNECT c##lab4_auditor/"$PWD_PRUEBA"@//localhost:1521/FREE
SELECT SYS_CONTEXT('USERENV', 'SESSION_USER') AS quien, SYS_CONTEXT('USERENV', 'CON_NAME') AS con_name FROM dual;
SELECT con_id, COUNT(*) AS tablespaces_cdb FROM cdb_tablespaces GROUP BY con_id ORDER BY con_id;
SELECT con_id, COUNT(*) AS sesiones FROM v\$session GROUP BY con_id ORDER BY con_id;
PROMPT (sin CONTAINER_DATA, un usuario común en la raíz solo ve los datos de la raíz y los de CON_ID 0)
PROMPT -- 5a. Con SET CONTAINER sí puede entrar en la PDB y mirar desde dentro
ALTER SESSION SET CONTAINER = FREEPDB1;
SELECT SYS_CONTEXT('USERENV', 'CON_NAME') AS con_name, COUNT(*) AS tablespaces FROM dba_tablespaces;
PROMPT
PROMPT ===== 6. Lo que tiene C##OPS_RO y no tiene c##lab4_auditor =====
CONNECT / AS SYSDBA
SELECT username, default_attr, all_containers FROM cdb_container_data
 WHERE username IN ('C##OPS_RO', 'C##LAB4_AUDITOR') ORDER BY username;
PROMPT (C##LAB4_AUDITOR no aparece: no tiene atributo CONTAINER_DATA. Se lo daría ALTER USER ... SET CONTAINER_DATA = ALL)
PROMPT
PROMPT ===== 7. Limpieza: se borran los dos usuarios de prueba =====
DROP USER c##lab4_auditor CASCADE;
ALTER SESSION SET CONTAINER = FREEPDB1;
DROP USER lab4_analista CASCADE;
SELECT COUNT(*) AS usuarios_lab4_restantes FROM cdb_users WHERE username LIKE '%LAB4%';
EXIT
SQL
