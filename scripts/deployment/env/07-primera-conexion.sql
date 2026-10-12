-- scripts/deployment/env/07-primera-conexion.sql
SET LINESIZE 200 PAGESIZE 100
PROMPT == 1. Version del motor ==
SELECT banner_full FROM v$version;
PROMPT == 2. Contenedor Oracle actual ==
SHOW CON_NAME
PROMPT == 3. Estado de la instancia ==
SELECT instance_name, status FROM v$instance;
PROMPT == 4. Usuario de aplicacion ALUMNO (para Database Actions) ==
SELECT username, account_status FROM dba_users WHERE username = 'ALUMNO';
EXIT
