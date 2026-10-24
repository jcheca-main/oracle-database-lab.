-- database/migrations/V003__cuentas_esquema_sin_password.sql
-- Corrige el Lab 3: V000 dejó contraseñas literales en el repositorio. Borrarlas del archivo no basta
-- (siguen en el historial de Git): la respuesta profesional es INVALIDARLAS.
-- Los propietarios de esquema pasan a ser cuentas de solo esquema (schema-only accounts, desde 18c):
-- poseen los objetos, pero nadie puede iniciar sesión con ellos.
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER USER admin_academia  NO AUTHENTICATION;
ALTER USER admin_clinica   NO AUTHENTICATION;
ALTER USER admin_retail    NO AUTHENTICATION;
ALTER USER admin_logistica NO AUTHENTICATION;
ALTER USER admin_fintech   NO AUTHENTICATION;
SET LINESIZE 120 PAGESIZE 50
COLUMN username FORMAT A16
COLUMN authentication_type FORMAT A20
COLUMN account_status FORMAT A16
SELECT username, authentication_type, account_status
  FROM dba_users WHERE username LIKE 'ADMIN\_%' ESCAPE '\' ORDER BY username;
EXIT
