-- scripts/deployment/env/12-ords-habilitar-alumno.sql
-- Requiere que app_pwd se defina ANTES de ejecutarlo. La contraseña nunca se escribe aquí.
SET VERIFY OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER = FREEPDB1;
DECLARE
 v_existe NUMBER;
BEGIN
 SELECT COUNT(*) INTO v_existe FROM dba_users WHERE username = 'ALUMNO';
 IF v_existe = 0 THEN
 EXECUTE IMMEDIATE
 'CREATE USER alumno IDENTIFIED BY "&&app_pwd" ' ||
 'DEFAULT TABLESPACE USERS QUOTA 100M ON USERS';
 EXECUTE IMMEDIATE
 'GRANT DB_DEVELOPER_ROLE, CREATE SESSION TO alumno';
 END IF;
END;
/
BEGIN
 ORDS_ADMIN.ENABLE_SCHEMA(
 p_enabled => TRUE,
 p_schema => 'ALUMNO',
 p_url_mapping_type => 'BASE_PATH',
 p_url_mapping_pattern => 'alumno',
 p_auto_rest_auth => TRUE);
 COMMIT;
END;
/
PROMPT == Verificacion: usuario de Database Actions ==
SELECT username, account_status, default_tablespace
 FROM dba_users WHERE username = 'ALUMNO';
EXIT
