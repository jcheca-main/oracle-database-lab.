-- scripts/lab6/07-objetos.sql — validez, dependencias, índices UNUSABLE y papelera (Unidad 5, 5.7.1)
-- SYSDBA:  bash scripts/ops/sysdba.sh scripts/lab6/07-objetos.sql "$EVID_LAB6/script/$(ts)_07-objetos.script.log"
-- Regla de oro: NUNCA se experimenta con la tabla de negocio. Se trabaja sobre una copia (ACA_EST_LAB6) que se borra al final.
SET LINESIZE 150 PAGESIZE 50 FEEDBACK ON
ALTER SESSION SET CONTAINER = FREEPDB1;
COLUMN object_name FORMAT A20
COLUMN object_type FORMAT A10
COLUMN paso FORMAT A44
COLUMN index_name FORMAT A18
COLUMN object_name_bin FORMAT A32
COLUMN original_name FORMAT A18
COLUMN type FORMAT A9
BEGIN
  FOR o IN (SELECT object_name, object_type FROM dba_objects WHERE owner = 'ADMIN_ACADEMIA'
              AND object_name IN ('ACA_EST_LAB6', 'V_ACTIVOS_LAB6', 'V_CONTACTO_LAB6', 'F_TOTAL_ACTIVOS_LAB6') AND object_type <> 'INDEX') LOOP
    EXECUTE IMMEDIATE 'DROP ' || o.object_type || ' admin_academia.' || o.object_name || CASE o.object_type WHEN 'TABLE' THEN ' PURGE' END;
  END LOOP;
END;
/
PROMPT == 1. Montaje: una copia de la tabla, dos vistas y una función que dependen de ella ==
CREATE TABLE admin_academia.aca_est_lab6 AS SELECT * FROM admin_academia.aca_estudiantes;
CREATE INDEX admin_academia.ix_est_lab6_estado ON admin_academia.aca_est_lab6 (estado);
CREATE VIEW admin_academia.v_activos_lab6 AS
  SELECT estudiante_id, nombres, apellidos FROM admin_academia.aca_est_lab6 WHERE estado = 'ACTIVO';
CREATE VIEW admin_academia.v_contacto_lab6 AS
  SELECT estudiante_id, email_institucional FROM admin_academia.aca_est_lab6;
CREATE FUNCTION admin_academia.f_total_activos_lab6 RETURN NUMBER AS n NUMBER;
BEGIN SELECT COUNT(*) INTO n FROM admin_academia.v_activos_lab6; RETURN n; END;
/
SET FEEDBACK OFF
SELECT object_name, object_type, status FROM dba_objects WHERE owner = 'ADMIN_ACADEMIA'
   AND object_name IN ('V_ACTIVOS_LAB6', 'V_CONTACTO_LAB6', 'F_TOTAL_ACTIVOS_LAB6') ORDER BY object_name;
PROMPT == 2. Columna nueva que nadie usa: Oracle NO invalida nada (dependencia de grano fino) ==
ALTER TABLE admin_academia.aca_est_lab6 ADD (telefono VARCHAR2(20));
SELECT object_name, object_type, status FROM dba_objects WHERE owner = 'ADMIN_ACADEMIA'
   AND object_name IN ('V_ACTIVOS_LAB6', 'V_CONTACTO_LAB6', 'F_TOTAL_ACTIVOS_LAB6') ORDER BY object_name;
PROMPT == 3. Se amplía email_institucional (solo la usa V_CONTACTO_LAB6) ==
ALTER TABLE admin_academia.aca_est_lab6 MODIFY (email_institucional VARCHAR2(200));
SELECT object_name, object_type, status FROM dba_objects WHERE owner = 'ADMIN_ACADEMIA'
   AND object_name IN ('V_ACTIVOS_LAB6', 'V_CONTACTO_LAB6', 'F_TOTAL_ACTIVOS_LAB6') ORDER BY object_name;
PROMPT == 4. Se amplía nombres (la usa V_ACTIVOS_LAB6... y la función, en cascada) ==
ALTER TABLE admin_academia.aca_est_lab6 MODIFY (nombres VARCHAR2(120));
SELECT object_name, object_type, status FROM dba_objects WHERE owner = 'ADMIN_ACADEMIA'
   AND object_name IN ('V_ACTIVOS_LAB6', 'V_CONTACTO_LAB6', 'F_TOTAL_ACTIVOS_LAB6') ORDER BY object_name;
PROMPT -- La cadena de dependencias que explica la cascada
COLUMN name FORMAT A22
COLUMN referenced_name FORMAT A16
COLUMN referenced_type FORMAT A15
SELECT name, type, referenced_name, referenced_type FROM dba_dependencies
 WHERE owner = 'ADMIN_ACADEMIA' AND name LIKE '%LAB6' AND referenced_owner <> 'SYS' ORDER BY name;
PROMPT == 5. Un usuario llama a la función: Oracle la recompila sola (en SU llamada, en hora punta) ==
SELECT admin_academia.f_total_activos_lab6 AS activos FROM dual;
SELECT object_name, object_type, status FROM dba_objects WHERE owner = 'ADMIN_ACADEMIA'
   AND object_name IN ('V_ACTIVOS_LAB6', 'V_CONTACTO_LAB6', 'F_TOTAL_ACTIVOS_LAB6') ORDER BY object_name;
PROMPT == 6. El DBA no espera a que un usuario tropiece: recompila el esquema ANTES de abrir el servicio ==
EXEC UTL_RECOMP.RECOMP_SERIAL('ADMIN_ACADEMIA')
SELECT object_name, object_type, status FROM dba_objects WHERE owner = 'ADMIN_ACADEMIA'
   AND object_name IN ('V_ACTIVOS_LAB6', 'V_CONTACTO_LAB6', 'F_TOTAL_ACTIVOS_LAB6') ORDER BY object_name;
PROMPT == 7. Índices UNUSABLE: un MOVE de la tabla cambia los ROWID y deja el índice inservible, sin dar error ==
ALTER TABLE admin_academia.aca_est_lab6 MOVE;
SELECT index_name, status FROM dba_indexes WHERE owner = 'ADMIN_ACADEMIA' AND table_name = 'ACA_EST_LAB6';
ALTER INDEX admin_academia.ix_est_lab6_estado REBUILD ONLINE;
SELECT index_name, status FROM dba_indexes WHERE owner = 'ADMIN_ACADEMIA' AND table_name = 'ACA_EST_LAB6';
PROMPT == 8. Papelera: DROP sin PURGE no libera el espacio ==
DROP VIEW admin_academia.v_activos_lab6;
DROP VIEW admin_academia.v_contacto_lab6;
DROP FUNCTION admin_academia.f_total_activos_lab6;
DROP TABLE admin_academia.aca_est_lab6;
SELECT original_name, object_name AS object_name_bin, type, ROUND(space * 8 / 1024, 1) AS mb FROM dba_recyclebin WHERE owner = 'ADMIN_ACADEMIA';
PURGE TABLE admin_academia.aca_est_lab6;
SELECT COUNT(*) AS en_papelera FROM dba_recyclebin WHERE owner = 'ADMIN_ACADEMIA';
PROMPT == 9. Validación final: inválidos de los esquemas de negocio (debe ser 0) ==
SELECT COUNT(*) AS invalidos_negocio FROM dba_objects
 WHERE status = 'INVALID' AND owner IN ('ADMIN_ACADEMIA', 'ADMIN_CLINICA', 'ADMIN_RETAIL', 'ADMIN_LOGISTICA', 'ADMIN_FINTECH', 'TIENDASUR', 'CARGA_HIST');
EXIT
