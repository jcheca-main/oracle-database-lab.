-- scripts/lab4/02-cuenta-observabilidad.sql — cuenta común de SOLO LECTURA para observar la instancia
-- Requiere DEFINE ops_pwd antes de ejecutarse (se inyecta desde config/.env). Se ejecuta en CDB$ROOT.
SET VERIFY OFF FEEDBACK ON
WHENEVER SQLERROR EXIT SQL.SQLCODE
DECLARE
  v_existe NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_existe FROM dba_users WHERE username = 'C##OPS_RO';
  IF v_existe = 0 THEN
    EXECUTE IMMEDIATE 'CREATE USER c##ops_ro IDENTIFIED BY "&&ops_pwd" CONTAINER = ALL';
  ELSE
    -- Si ya existía (segunda ejecución), su contraseña se alinea con config/.env: si no, ro.sh fallaría con ORA-01017
    EXECUTE IMMEDIATE 'ALTER USER c##ops_ro IDENTIFIED BY "&&ops_pwd" CONTAINER = ALL';
  END IF;
END;
/
GRANT CREATE SESSION, SET CONTAINER TO c##ops_ro CONTAINER = ALL;
GRANT SELECT_CATALOG_ROLE TO c##ops_ro CONTAINER = ALL;
ALTER USER c##ops_ro SET CONTAINER_DATA = ALL CONTAINER = CURRENT;
PROMPT == Verificación: la cuenta existe en todos los contenedores ==
SET LINESIZE 120 PAGESIZE 50
COLUMN username FORMAT A12
COLUMN contenedor FORMAT A12
SELECT u.con_id, c.name AS contenedor, u.username, u.common, u.account_status
  FROM cdb_users u JOIN v$containers c ON c.con_id = u.con_id
 WHERE u.username = 'C##OPS_RO' ORDER BY u.con_id;
EXIT
