-- scripts/lab6/08-diagnostico.sql — la evidencia de un bloqueo, en solo lectura y ANTES de tocar nada (Unidad 5, 5.7.7)
-- bash scripts/ops/ro.sh scripts/lab6/08-diagnostico.sql | tee "$EVID_LAB6/script/$(ts)_08-diagnostico.script.log"
SET TERMOUT OFF
SET SQLFORMAT DEFAULT
SET TERMOUT ON
SET LINESIZE 200 PAGESIZE 100 FEEDBACK OFF
COLUMN username FORMAT A13
COLUMN module FORMAT A11
COLUMN action FORMAT A14
COLUMN event FORMAT A30
COLUMN wait_class FORMAT A11
COLUMN state FORMAT A8
COLUMN status FORMAT A8
COLUMN object_name FORMAT A16
COLUMN t FORMAT A8
COLUMN sid FORMAT 9999
COLUMN serial# FORMAT 99999
COLUMN seg FORMAT 9999
COLUMN bloqueador FORMAT 9999 HEADING BLOQ
COLUMN name FORMAT A16
COLUMN arrancado FORMAT A9
COLUMN account_status FORMAT A16
COLUMN profile FORMAT A13
COLUMN intentos_permitidos FORMAT A19
PROMPT == 1. ¿Quién espera, en qué y por culpa de quién? ==
SELECT sid, serial#, username, module, action, event, wait_class, seconds_in_wait AS seg, blocking_session AS bloqueador
  FROM v$session WHERE username IN ('APP_ACADEMIA', 'ANA_GARCIA') OR sid IN (SELECT blocking_session FROM v$session) ORDER BY sid;
PROMPT == 2. ¿Por qué fila exacta? ==
SELECT s.sid, o.object_name, s.row_wait_file# AS archivo, s.row_wait_block# AS bloque, s.row_wait_row# AS fila
  FROM v$session s JOIN cdb_objects o ON o.object_id = s.row_wait_obj# AND o.con_id = s.con_id
 WHERE s.blocking_session IS NOT NULL;
PROMPT == 3. Los bloqueos: quién TIENE el TX (lmode 6, block 1) y quién lo PIDE (request 6) ==
SELECT sid, type, id1, id2, lmode, request, block FROM v$lock
 WHERE type IN ('TX', 'TM') AND sid IN (SELECT sid FROM v$session WHERE username IN ('APP_ACADEMIA', 'ANA_GARCIA')) ORDER BY sid, type;
PROMPT == 4. ¿Cuánto trabajo se desharía si se termina al bloqueador? ==
SELECT s.sid, s.module, t.used_ublk, t.used_urec, t.start_time FROM v$transaction t JOIN v$session s ON s.taddr = t.addr;
PROMPT == 5. ASH lo guardó segundo a segundo (aunque el bloqueo ya no exista, esto queda) ==
SELECT TO_CHAR(sample_time, 'HH24:MI:SS') AS t, session_id AS sid, event, blocking_session AS bloqueador
  FROM v$active_session_history WHERE event LIKE 'enq: TX%' ORDER BY sample_time DESC FETCH FIRST 5 ROWS ONLY;
PROMPT == 6. Servicios: ¿están arrancados todos los que existen? (NO = existe, pero el listener no lo anuncia) ==
SELECT s.con_id, s.name, CASE WHEN a.name IS NULL THEN 'NO' ELSE 'SI' END AS arrancado
  FROM cdb_services s LEFT JOIN v$active_services a ON UPPER(a.name) = UPPER(s.name) AND a.con_id = s.con_id
 WHERE s.con_id > 2 ORDER BY s.con_id, s.name;
PROMPT == 7. Cuentas que no son de Oracle y no están OPEN (LOCKED = a mano; LOCKED(TIMED) = intentos fallidos) ==
SELECT u.con_id, u.username, u.account_status, TO_CHAR(u.lock_date, 'YYYY-MM-DD HH24:MI') AS bloqueo, u.profile,
       p.limit AS intentos_permitidos
  FROM cdb_users u JOIN cdb_profiles p ON p.profile = u.profile AND p.con_id = u.con_id AND p.resource_name = 'FAILED_LOGIN_ATTEMPTS'
 WHERE u.oracle_maintained = 'N' AND u.account_status <> 'OPEN' AND u.authentication_type <> 'NONE'
 ORDER BY u.con_id, u.username;
