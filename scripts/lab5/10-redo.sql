-- scripts/lab5/10-redo.sql — grupos y miembros del redo log, cambio de log y errores típicos
-- Se ejecuta como SYSDBA: bash scripts/ops/sysdba.sh <este archivo> <evidencia>
-- Idempotente: solo añade un segundo miembro a los grupos que tengan uno.
WHENEVER SQLERROR CONTINUE
SET LINESIZE 160 PAGESIZE 100 FEEDBACK OFF SERVEROUTPUT ON
COLUMN member FORMAT A44
COLUMN status FORMAT A10
COLUMN archived FORMAT A8
COLUMN type FORMAT A7
PROMPT
PROMPT ===== 1. Grupos (v$log) y miembros (v$logfile) =====
SELECT group#, thread#, sequence#, ROUND(bytes / 1048576) AS mb, members, archived, status, first_change#
  FROM v$log ORDER BY group#;
SELECT group#, member, type, status FROM v$logfile ORDER BY group#, member;
PROMPT
PROMPT ===== 2. Multiplexar: un segundo MIEMBRO en cada grupo (mismo contenido, escritos a la vez por LGWR) =====
DECLARE
  v_ruta VARCHAR2(400);
  v_n    PLS_INTEGER := 0;
BEGIN
  FOR g IN (SELECT group# FROM v$log WHERE members = 1 ORDER BY group#) LOOP
    SELECT REGEXP_REPLACE(MIN(member), '\.log$', 'b.log') INTO v_ruta FROM v$logfile WHERE group# = g.group#;
    EXECUTE IMMEDIATE 'ALTER DATABASE ADD LOGFILE MEMBER ''' || v_ruta || ''' TO GROUP ' || g.group#;
    DBMS_OUTPUT.PUT_LINE('Grupo ' || g.group# || ': añadido ' || v_ruta);
    v_n := v_n + 1;
  END LOOP;
  IF v_n = 0 THEN DBMS_OUTPUT.PUT_LINE('Todos los grupos ya tienen dos miembros: nada que añadir.'); END IF;
END;
/
PROMPT -- Un miembro recién añadido figura como INVALID hasta que LGWR escribe en él por primera vez
SELECT group#, member, status FROM v$logfile ORDER BY group#, member;
PROMPT
PROMPT ===== 3. Cambio de log (log switch): el grupo CURRENT pasa al siguiente, en círculo =====
ALTER SYSTEM SWITCH LOGFILE;
SELECT group#, sequence#, status FROM v$log ORDER BY group#;
ALTER SYSTEM SWITCH LOGFILE;
SELECT group#, sequence#, status FROM v$log ORDER BY group#;
PROMPT -- Tras dos cambios, todos los miembros ya se han escrito: ninguno queda INVALID
SELECT group#, member, status FROM v$logfile ORDER BY group#, member;
PROMPT
PROMPT ===== 4. Errores que el examen pregunta (ninguno cambia nada: Oracle se protege) =====
DECLARE
  v_cur NUMBER; v_ina NUMBER; v_mem VARCHAR2(400);
  PROCEDURE intenta(p_titulo VARCHAR2, p_sql VARCHAR2) IS
  BEGIN
    EXECUTE IMMEDIATE p_sql;
    DBMS_OUTPUT.PUT_LINE(p_titulo || ' -> se ejecutó (¡no debería!)');
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE(p_titulo || ' -> ' || SQLERRM);
  END;
BEGIN
  SELECT group# INTO v_cur FROM v$log WHERE status = 'CURRENT';
  SELECT MIN(member) INTO v_mem FROM v$logfile WHERE group# = v_cur;
  SELECT MIN(group#) INTO v_ina FROM v$log WHERE status <> 'CURRENT';
  intenta('4a. Borrar el grupo CURRENT', 'ALTER DATABASE DROP LOGFILE GROUP ' || v_cur);
  intenta('4b. Borrar un miembro del grupo CURRENT', 'ALTER DATABASE DROP LOGFILE MEMBER ''' || v_mem || '''');
  intenta('4c. Borrar otro grupo dejando uno solo', 'ALTER DATABASE DROP LOGFILE GROUP ' || v_ina);
END;
/
PROMPT
PROMPT ===== 5. Historial de cambios de log (v$log_history) =====
SELECT sequence#, first_change#, TO_CHAR(first_time, 'YYYY-MM-DD HH24:MI:SS') AS inicio
  FROM v$log_history ORDER BY sequence# DESC FETCH FIRST 5 ROWS ONLY;
EXIT
