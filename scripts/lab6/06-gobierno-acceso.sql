-- scripts/lab6/06-gobierno-acceso.sql — perfil para personas, roles funcionales, cuenta nominal y pago de la deuda de acceso
-- (Unidad 5, 5.6.2 a 5.6.6). Requiere DEFINE ana_pwd (la inyecta 06-gobierno-acceso.sh). Repetible.
SET LINESIZE 160 PAGESIZE 100 FEEDBACK ON VERIFY OFF
ALTER SESSION SET CONTAINER = FREEPDB1;
SET SERVEROUTPUT ON
COLUMN resource_name FORMAT A26
COLUMN limit FORMAT A26
PROMPT == 1. No supongas los valores por defecto: consúltalos (perfil DEFAULT, parámetros de contraseña) ==
SELECT resource_name, limit FROM dba_profiles WHERE profile = 'DEFAULT' AND resource_type = 'PASSWORD' ORDER BY resource_name;
PROMPT == 2. Un perfil para PERSONAS (bloqueo de 1 minuto: solo en laboratorio) ==
DECLARE n NUMBER; v VARCHAR2(400);
BEGIN
  SELECT COUNT(*) INTO n FROM dba_profiles WHERE profile = 'PRF_PERSONAS';
  v := CASE WHEN n = 0 THEN 'CREATE' ELSE 'ALTER' END || ' PROFILE prf_personas LIMIT
         FAILED_LOGIN_ATTEMPTS 3 PASSWORD_LOCK_TIME 1/1440 PASSWORD_LIFE_TIME 90 PASSWORD_GRACE_TIME 7
         INACTIVE_ACCOUNT_TIME 90 PASSWORD_VERIFY_FUNCTION ora12c_verify_function';
  EXECUTE IMMEDIATE v;
  DBMS_OUTPUT.PUT_LINE('Perfil PRF_PERSONAS ' || CASE WHEN n = 0 THEN 'creado' ELSE 'actualizado' END);
END;
/
PROMPT -- La función de verificación rechaza una contraseña débil (error esperado: ORA-28003)
CREATE USER prueba_debil IDENTIFIED BY "corta" PROFILE prf_personas;
PROMPT == 3. Roles FUNCIONALES: lo que se da por rol se administra; lo que se da disperso se persigue ==
DECLARE
  PROCEDURE rol(p VARCHAR2) IS n NUMBER;
  BEGIN
    SELECT COUNT(*) INTO n FROM dba_roles WHERE role = UPPER(p);
    IF n = 0 THEN EXECUTE IMMEDIATE 'CREATE ROLE ' || p; END IF;
  END;
BEGIN
  rol('rol_lectura_academia'); rol('rol_secretaria_academia'); rol('rol_app_academia');
END;
/
-- Privilegio de ESQUEMA (23ai): leer todas las tablas de ADMIN_ACADEMIA, también las que se creen mañana
GRANT SELECT ANY TABLE ON SCHEMA admin_academia TO rol_lectura_academia;
-- Secretaría: leer Academia y cambiar SOLO la columna estado de los estudiantes
GRANT rol_lectura_academia TO rol_secretaria_academia;
GRANT UPDATE (estado) ON admin_academia.aca_estudiantes TO rol_secretaria_academia;
-- Aplicación: exactamente lo que usa
GRANT SELECT, UPDATE ON admin_academia.aca_estudiantes TO rol_app_academia;
PROMPT == 4. Alta (joiner): una cuenta NOMINAL para una persona de secretaría ==
DECLARE n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM dba_users WHERE username = 'ANA_GARCIA';
  IF n = 0 THEN
    EXECUTE IMMEDIATE 'CREATE USER ana_garcia IDENTIFIED BY "&&ana_pwd" DEFAULT TABLESPACE users QUOTA 0 ON users PROFILE prf_personas';
  ELSE
    EXECUTE IMMEDIATE 'ALTER USER ana_garcia IDENTIFIED BY "&&ana_pwd" PROFILE prf_personas ACCOUNT UNLOCK';
  END IF;
END;
/
GRANT CREATE SESSION, rol_secretaria_academia TO ana_garcia;
PROMPT == 5. Pagar la deuda de acceso: APP_ACADEMIA pasa de privilegios sueltos a UN rol ==
DECLARE
  PROCEDURE quitar(p VARCHAR2) IS BEGIN EXECUTE IMMEDIATE p; EXCEPTION WHEN OTHERS THEN NULL; END;   -- repetible: si ya no lo tiene, sigue
BEGIN
  quitar('REVOKE SELECT, UPDATE ON admin_academia.aca_estudiantes FROM app_academia');
  quitar('REVOKE INSERT ON carga_hist.registro FROM app_academia');
  quitar('REVOKE RESUMABLE FROM app_academia');
END;
/
GRANT rol_app_academia TO app_academia;
PROMPT == 6. Resultado: quién tiene qué (roles, privilegios de objeto, de esquema y de sistema) ==
COLUMN grantee FORMAT A24
COLUMN granted_role FORMAT A24
COLUMN privilege FORMAT A18
COLUMN table_name FORMAT A16
COLUMN column_name FORMAT A8
COLUMN schema FORMAT A15
COLUMN default_role FORMAT A7
SELECT grantee, granted_role, default_role FROM dba_role_privs
 WHERE grantee IN ('ANA_GARCIA', 'APP_ACADEMIA', 'ROL_SECRETARIA_ACADEMIA') ORDER BY grantee, granted_role;
SELECT grantee, privilege, schema FROM dba_schema_privs WHERE grantee LIKE 'ROL\_%' ESCAPE '\';
SELECT grantee, table_name, privilege FROM dba_tab_privs
 WHERE grantee IN ('ANA_GARCIA', 'APP_ACADEMIA', 'ROL_APP_ACADEMIA', 'ROL_SECRETARIA_ACADEMIA') ORDER BY grantee, table_name, privilege;
SELECT grantee, table_name, column_name, privilege FROM dba_col_privs WHERE grantee = 'ROL_SECRETARIA_ACADEMIA';
SELECT grantee, privilege FROM dba_sys_privs WHERE grantee IN ('ANA_GARCIA', 'APP_ACADEMIA') ORDER BY grantee, privilege;
COLUMN username FORMAT A13
COLUMN profile FORMAT A13
COLUMN account_status FORMAT A16
COLUMN authentication_type FORMAT A19
SELECT username, profile, account_status, authentication_type FROM dba_users WHERE username IN ('ANA_GARCIA', 'APP_ACADEMIA') ORDER BY 1;
EXIT
