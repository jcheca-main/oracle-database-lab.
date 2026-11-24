-- scripts/lab6/03-servicio.sql — un servicio por aplicación: academia_app (Unidad 5, 5.3.3)
-- SYSDBA:  bash scripts/ops/sysdba.sh scripts/lab6/03-servicio.sql "$EVID_LAB6/script/$(ts)_03-servicio.script.log"
-- Idempotente: si el servicio ya existe, solo lo arranca.
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET LINESIZE 150 PAGESIZE 100 FEEDBACK ON
ALTER SESSION SET CONTAINER = FREEPDB1;
-- SERVEROUTPUT se activa DESPUÉS de cambiar de contenedor: el cambio lo desactiva
SET SERVEROUTPUT ON
COLUMN name FORMAT A16
COLUMN network_name FORMAT A16
COLUMN pdb FORMAT A10
DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM dba_services WHERE name = 'academia_app';
  IF n = 0 THEN
    DBMS_SERVICE.CREATE_SERVICE(service_name => 'academia_app', network_name => 'academia_app');
    DBMS_OUTPUT.PUT_LINE('Servicio academia_app creado');
  END IF;
  SELECT COUNT(*) INTO n FROM v$active_services WHERE name = 'academia_app';
  IF n = 0 THEN
    DBMS_SERVICE.START_SERVICE('academia_app');
    DBMS_OUTPUT.PUT_LINE('Servicio academia_app arrancado');
  ELSE
    DBMS_OUTPUT.PUT_LINE('Servicio academia_app ya estaba arrancado');
  END IF;
END;
/
PROMPT == Qué servicios EXISTEN (diccionario de la PDB) ==
SELECT name, network_name, pdb FROM dba_services ORDER BY name;
PROMPT == Cuáles están ARRANCADOS ahora (y por tanto se anuncian al listener) ==
SELECT name, con_id FROM v$active_services ORDER BY name;
PROMPT == Que sobreviva a un reinicio: se guarda el estado CON el servicio arrancado ==
ALTER PLUGGABLE DATABASE FREEPDB1 SAVE STATE;
EXIT
