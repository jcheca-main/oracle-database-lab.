-- scripts/lab5/12-sesion-b.sql — SESIÓN B: observa mientras A tiene la transacción abierta
WHENEVER SQLERROR CONTINUE
SET LINESIZE 160 PAGESIZE 100 FEEDBACK OFF
COLUMN estado FORMAT A10
COLUMN tipo FORMAT A4
COLUMN objeto FORMAT A16
COLUMN inicio FORMAT A20
ALTER SESSION SET CONTAINER = FREEPDB1;
PROMPT
PROMPT [B] 1. ¿Qué ve B? El valor CONFIRMADO, reconstruido con el undo (lectura consistente)
SELECT estudiante_id, estado FROM admin_academia.aca_estudiantes WHERE estudiante_id = 101;
PROMPT
PROMPT [B] 2. La transacción de A: bloques y registros de undo que ya consume (v$transaction)
SELECT t.xidusn AS segmento_undo, t.used_ublk AS bloques_undo, t.used_urec AS registros_undo,
       t.start_time AS inicio, s.sid AS sid_de_a
  FROM v$transaction t JOIN v$session s ON s.taddr = t.addr;
PROMPT
PROMPT [B] 3. Bloqueos de A: TM (tabla, modo 3 = row exclusive) y TX (fila, modo 6 = exclusive)
SELECT l.sid, l.type AS tipo, l.lmode, o.object_name AS objeto
  FROM v$lock l LEFT JOIN dba_objects o ON o.object_id = l.id1 AND l.type = 'TM'
 WHERE l.type IN ('TX', 'TM') AND l.sid <> SYS_CONTEXT('USERENV', 'SID') ORDER BY l.type;
PROMPT
PROMPT [B] 4. B intenta bloquear la misma fila: esperar como mucho 3 s (error esperado: ORA-00054, fila bloqueada por A)
SELECT estado FROM admin_academia.aca_estudiantes WHERE estudiante_id = 101 FOR UPDATE WAIT 3;
PROMPT
PROMPT [B] 5. Esperamos a que A confirme...
EXEC DBMS_SESSION.SLEEP(22)
SELECT estudiante_id, estado FROM admin_academia.aca_estudiantes WHERE estudiante_id = 101;
PROMPT
PROMPT [B] 6. Consulta de flashback (Flashback Query): la fila tal como era hace 40 s, leída del undo
SELECT estudiante_id, estado FROM admin_academia.aca_estudiantes
  AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '40' SECOND) WHERE estudiante_id = 101;
PROMPT
PROMPT [B] 7. Reparación lógica con el undo: devolver la fila a su valor anterior (deja el lab repetible)
UPDATE admin_academia.aca_estudiantes e
   SET estado = (SELECT estado FROM admin_academia.aca_estudiantes AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '40' SECOND)
                  WHERE estudiante_id = 101)
 WHERE e.estudiante_id = 101;
COMMIT;
SELECT estudiante_id, estado FROM admin_academia.aca_estudiantes WHERE estudiante_id = 101;
PROMPT
PROMPT [B] 8. ¿Cuánto tiempo intenta Oracle conservar el undo? (undo_retention y v$undostat)
COLUMN name FORMAT A20
COLUMN value FORMAT A10
SELECT name, value FROM v$parameter WHERE name IN ('undo_retention', 'undo_management', 'undo_tablespace');
SELECT TO_CHAR(begin_time, 'HH24:MI') AS desde, TO_CHAR(end_time, 'HH24:MI') AS hasta, undoblks, txncount,
       maxquerylen AS consulta_mas_larga_s, tuned_undoretention AS retencion_ajustada_s, ssolderrcnt AS ora_01555
  FROM v$undostat ORDER BY begin_time DESC FETCH FIRST 3 ROWS ONLY;
EXIT
