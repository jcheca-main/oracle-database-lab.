-- scripts/lab4/11-ampliar-ops-ro.sql — mínimo privilegio en la práctica: se concede SOLO lo que hace falta para leer el alert log
-- SELECT_CATALOG_ROLE no incluye V$DIAG_ALERT_EXT (el alert log en forma de vista). Se concede ese objeto y nada más.
-- Se ejecuta como SYSDBA: bash scripts/ops/sysdba.sh <este archivo> <evidencia>
WHENEVER SQLERROR EXIT FAILURE
GRANT SELECT ON sys.v_$diag_alert_ext TO c##ops_ro CONTAINER = ALL;
SET LINESIZE 120
COLUMN grantee FORMAT A12
COLUMN table_name FORMAT A20
COLUMN privilege FORMAT A10
SELECT grantee, table_name, privilege, common FROM dba_tab_privs WHERE grantee = 'C##OPS_RO';
EXIT
