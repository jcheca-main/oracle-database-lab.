-- scripts/lab4/09-reto-sesion-larga.sql — reto de la Parte H: localizar la sesión SYSDBA que ejecuta la consulta larga (C##OPS_RO)
@scripts/ops/marca
SPOOL docs/bitacora/lab4/evidencia/spool/&marca._09-reto-sesion-larga.spool.log
SET SQLFORMAT DEFAULT
SET LINESIZE 180 PAGESIZE 100 FEEDBACK OFF
COLUMN username FORMAT A12
COLUMN machine FORMAT A14
COLUMN program FORMAT A34
COLUMN spid FORMAT A8
COLUMN status FORMAT A8
PROMPT
PROMPT == 1. Mis propios datos (la "terminal 2" soy yo: C##OPS_RO) ==
SELECT s.sid, s.serial#, s.username, s.machine, s.program, s.status, p.spid
  FROM v$session s JOIN v$process p ON p.addr = s.paddr
 WHERE s.sid = SYS_CONTEXT('USERENV', 'SID');
PROMPT
PROMPT == 2. Todas las sesiones de usuario activas ordenadas por PGA (la consultona, primero) ==
SELECT s.sid, s.serial#, s.username, s.machine, s.program, s.status, p.spid,
       ROUND(p.pga_used_mem/1048576,1)  AS pga_used_mb,
       ROUND(p.pga_alloc_mem/1048576,1) AS pga_alloc_mb,
       ROUND(p.pga_max_mem/1048576,1)   AS pga_max_mb
  FROM v$session s JOIN v$process p ON p.addr = s.paddr
 WHERE s.type = 'USER' AND s.sid <> SYS_CONTEXT('USERENV', 'SID')
 ORDER BY p.pga_alloc_mem DESC;
PROMPT
PROMPT == 3. Los tres valores del diagnóstico: SID, SPID (Linux) y PGA de la sesión que está trabajando ==
SELECT s.sid, s.serial#, s.username, s.program, p.spid,
       ROUND(p.pga_used_mem/1048576,1)  AS pga_used_mb,
       ROUND(p.pga_alloc_mem/1048576,1) AS pga_alloc_mb
  FROM v$session s JOIN v$process p ON p.addr = s.paddr
 WHERE s.type = 'USER' AND s.sid <> SYS_CONTEXT('USERENV', 'SID')
   AND s.status = 'ACTIVE' AND s.username = 'SYS';
PROMPT
PROMPT (SPID = PID real de Linux dentro del contenedor; cruza con 09-procesos-so.sh)
SPOOL OFF
