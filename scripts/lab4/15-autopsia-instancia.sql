-- scripts/lab4/15-autopsia-instancia.sql — autopsia en una página: instancia, memoria, procesos, archivos, almacenamiento, índices, seguridad y red
-- SQLcl · C##OPS_RO · servicio FREE. Solo lectura: se puede lanzar en cualquier momento, también en producción.
-- Uso: bash scripts/ops/ro.sh scripts/lab4/15-autopsia-instancia.sql
@scripts/ops/marca
SPOOL docs/bitacora/lab4/evidencia/spool/&marca._15-autopsia-instancia.spool.log
SET SQLFORMAT DEFAULT
SET LINESIZE 170 PAGESIZE 100 FEEDBACK OFF TAB OFF
COLUMN instancia FORMAT A9
COLUMN host_name FORMAT A14
COLUMN version FORMAT A12
COLUMN arranque FORMAT A17
COLUMN nombre FORMAT A40
COLUMN contenedor FORMAT A10
COLUMN tipo FORMAT A24
COLUMN force_logging FORMAT A7
COLUMN flashback_on FORMAT A9
COLUMN codigo FORMAT A10
COLUMN tablespace_name FORMAT A16
COLUMN owner FORMAT A16
COLUMN name FORMAT A30
COLUMN value FORMAT A60 TRUNCATED
COLUMN procesos FORMAT A90 WORD_WRAPPED
COLUMN network_name FORMAT A34
PROMPT
PROMPT ===== 1. IDENTIDAD: la instancia (procesos + memoria) y la base (archivos) son cosas distintas =====
SELECT instance_name AS instancia, host_name, version_full AS version, TO_CHAR(startup_time, 'YYYY-MM-DD HH24:MI') AS arranque,
       ROUND(SYSDATE - startup_time, 2) AS dias_arriba, status, database_status FROM v$instance;
SELECT name, dbid, cdb, log_mode, open_mode, force_logging, flashback_on, database_role FROM v$database;
SELECT con_id, name AS contenedor, open_mode, ROUND(total_size / 1048576) AS mb FROM v$containers ORDER BY con_id;
PROMPT
PROMPT ===== 2. MEMORIA: SGA (compartida) y PGA (privada de cada proceso) =====
SELECT name AS nombre, ROUND(bytes / 1048576) AS mb, resizeable FROM v$sgainfo
 WHERE name IN ('Fixed SGA Size', 'Redo Buffers', 'Buffer Cache Size', 'Shared Pool Size', 'Large Pool Size',
                'Java Pool Size', 'In-Memory Area Size', 'Maximum SGA Size', 'Free SGA Memory Available')
 ORDER BY bytes DESC;
SELECT name AS nombre, ROUND(value / 1048576) AS mb FROM v$pgastat
 WHERE con_id = 0 AND name IN ('aggregate PGA target parameter', 'total PGA allocated', 'maximum PGA allocated');
PROMPT
PROMPT ===== 3. PROCESOS: segundo plano (background) frente a servidores de sesiones =====
SELECT CASE WHEN background = '1' THEN 'segundo plano' ELSE 'servidor / otros' END AS tipo, COUNT(*) AS procesos_n
  FROM v$process GROUP BY CASE WHEN background = '1' THEN 'segundo plano' ELSE 'servidor / otros' END;
SELECT LISTAGG(pname, ' ') WITHIN GROUP (ORDER BY pname) AS procesos FROM v$process
 WHERE pname IN ('PMON', 'SMON', 'DBW0', 'LGWR', 'CKPT', 'MMON', 'MMNL', 'RECO', 'LREG', 'ARC0', 'ARC1', 'DBRM', 'PSP0', 'VKTM');
PROMPT
PROMPT ===== 4. ARCHIVOS: los que SON la base y los que la acompañan =====
SELECT tipo, COUNT(*) AS archivos, ROUND(SUM(mb)) AS mb FROM (
  SELECT 'datafile' AS tipo, bytes / 1048576 AS mb FROM v$datafile
  UNION ALL SELECT 'tempfile', bytes / 1048576 FROM v$tempfile
  UNION ALL SELECT 'control file', block_size * file_size_blks / 1048576 FROM v$controlfile
  UNION ALL SELECT 'redo log (miembro)', l.bytes / 1048576 FROM v$logfile f JOIN v$log l ON l.group# = f.group#
  UNION ALL SELECT 'archived log (en disco)', blocks * block_size / 1048576 FROM v$archived_log WHERE deleted = 'NO' AND name IS NOT NULL)
 GROUP BY tipo ORDER BY tipo;
SELECT name, value FROM v$parameter
 WHERE name IN ('spfile', 'db_recovery_file_dest', 'db_recovery_file_dest_size', 'diagnostic_dest', 'db_block_size', 'control_files');
PROMPT
PROMPT ===== 5. ALMACENAMIENTO LÓGICO: tablespaces llenos y qué tipo de segmentos hay en cada contenedor =====
SELECT u.con_id, u.tablespace_name, ROUND(u.used_space * 8192 / 1048576) AS mb_usados,
       ROUND(u.tablespace_size * 8192 / 1048576) AS mb_maximo, ROUND(u.used_percent, 1) AS pct_usado,
       CASE WHEN u.used_percent > 85 THEN '<-- vigilar' END AS alerta
  FROM cdb_tablespace_usage_metrics u ORDER BY u.con_id, u.used_percent DESC;
SELECT con_id, segment_type AS tipo, COUNT(*) AS segmentos, ROUND(SUM(bytes) / 1048576) AS mb
  FROM cdb_segments WHERE segment_type IN ('TABLE', 'INDEX', 'LOBSEGMENT', 'LOBINDEX', 'TABLE PARTITION', 'INDEX PARTITION', 'ROLLBACK', 'TYPE2 UNDO')
 GROUP BY con_id, segment_type ORDER BY con_id, mb DESC;
PROMPT
PROMPT ===== 6. ÍNDICES de los esquemas de negocio: cuántos, cuánto pesan y cuáles tienen mal factor de agrupamiento =====
SELECT i.owner, COUNT(*) AS indices, SUM(CASE WHEN i.uniqueness = 'UNIQUE' THEN 1 ELSE 0 END) AS unicos,
       MAX(i.blevel) + 1 AS altura_max,
       SUM(CASE WHEN i.clustering_factor > 0.5 * t.num_rows THEN 1 ELSE 0 END) AS cf_cercano_a_filas,
       SUM(CASE WHEN i.status NOT IN ('VALID', 'N/A') THEN 1 ELSE 0 END) AS no_validos
  FROM cdb_indexes i JOIN cdb_tables t ON t.con_id = i.con_id AND t.owner = i.table_owner AND t.table_name = i.table_name
 WHERE i.owner LIKE 'ADMIN\_%' ESCAPE '\' GROUP BY i.owner ORDER BY i.owner;
PROMPT (ALTURA_MAX vacía = el esquema no tiene estadísticas: el optimizador va a ciegas. Lo arregla DBMS_STATS.GATHER_SCHEMA_STATS)
PROMPT
PROMPT ===== 7. SEGURIDAD: cuentas comunes y locales, y quién tiene el rol DBA =====
SELECT con_id, common, COUNT(*) AS usuarios, SUM(CASE WHEN oracle_maintained = 'N' THEN 1 ELSE 0 END) AS de_la_casa
  FROM cdb_users GROUP BY con_id, common ORDER BY con_id, common;
SELECT r.con_id, r.grantee AS owner FROM cdb_role_privs r
  JOIN cdb_users u ON u.con_id = r.con_id AND u.username = r.grantee
 WHERE r.granted_role = 'DBA' AND u.oracle_maintained = 'N' ORDER BY 1, 2;
PROMPT (Ninguna fila = ninguna cuenta de la casa tiene DBA, solo las que mantiene Oracle: así debe ser)
PROMPT
PROMPT ===== 8. RED: los servicios que anuncia el listener =====
SELECT con_id, name, network_name FROM v$active_services ORDER BY con_id, name;
PROMPT
PROMPT ===== 9. CONFIGURACIÓN: parámetros que alguien cambió (no están en su valor por defecto) =====
SELECT name, value FROM v$parameter WHERE isdefault = 'FALSE' ORDER BY name;
PROMPT
PROMPT ===== 10. SALUD: errores ORA- en el alert log de las últimas 24 horas =====
SELECT COUNT(*) AS errores_ora_24h FROM v$diag_alert_ext
 WHERE originating_timestamp > SYSTIMESTAMP - INTERVAL '1' DAY AND message_text LIKE '%ORA-%';
SELECT REGEXP_SUBSTR(message_text, 'ORA-[0-9]+') AS codigo, COUNT(*) AS veces, TO_CHAR(MAX(originating_timestamp), 'YYYY-MM-DD HH24:MI') AS ultima_vez
  FROM v$diag_alert_ext WHERE originating_timestamp > SYSTIMESTAMP - INTERVAL '1' DAY AND message_text LIKE '%ORA-%'
 GROUP BY REGEXP_SUBSTR(message_text, 'ORA-[0-9]+') ORDER BY veces DESC FETCH FIRST 5 ROWS ONLY;
PROMPT (Cada código se busca en https://docs.oracle.com/error-help/db/ora-NNNNN/ antes de tocar nada)
SPOOL OFF
