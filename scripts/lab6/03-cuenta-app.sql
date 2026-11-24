-- scripts/lab6/03-cuenta-app.sql — la cuenta LOCAL de la aplicación de Academia (Unidad 5, 5.3.6 y 5.6.2)
-- Requiere DEFINE app_pwd (la inyecta 03-cuenta-app.sh desde config/.env). Idempotente.
-- Los privilegios se conceden aquí DIRECTAMENTE a propósito: es la «deuda de acceso» que pagarás en la Parte G.
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET VERIFY OFF FEEDBACK ON LINESIZE 150 PAGESIZE 50
PROMPT == En la raíz: ¿qué prefijo exige Oracle a los usuarios comunes? ==
COLUMN name FORMAT A20
COLUMN value FORMAT A12
SELECT name, NVL(value, '(vacío)') AS value FROM v$parameter WHERE name = 'common_user_prefix';
ALTER SESSION SET CONTAINER = FREEPDB1;
DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM dba_users WHERE username = 'APP_ACADEMIA';
  IF n = 0 THEN
    EXECUTE IMMEDIATE 'CREATE USER app_academia IDENTIFIED BY "&&app_pwd" DEFAULT TABLESPACE users QUOTA 0 ON users';
  ELSE
    EXECUTE IMMEDIATE 'ALTER USER app_academia IDENTIFIED BY "&&app_pwd" ACCOUNT UNLOCK';
  END IF;
END;
/
GRANT CREATE SESSION TO app_academia;
GRANT SELECT, UPDATE ON admin_academia.aca_estudiantes TO app_academia;
COLUMN username FORMAT A14
COLUMN common FORMAT A6
COLUMN account_status FORMAT A16
COLUMN default_tablespace FORMAT A12
COLUMN authentication_type FORMAT A19
PROMPT == La cuenta es LOCAL (COMMON = NO): solo existe en FREEPDB1 ==
SELECT username, common, account_status, default_tablespace, authentication_type FROM dba_users WHERE username = 'APP_ACADEMIA';
EXIT
