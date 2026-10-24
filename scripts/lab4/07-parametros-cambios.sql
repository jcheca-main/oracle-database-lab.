-- scripts/lab4/07-parametros-cambios.sql — SCOPE=MEMORY|SPFILE|BOTH, estáticos, RESET, nivel PDB y PFILE
-- Se ejecuta como SYSDBA: bash scripts/ops/sysdba.sh <este archivo> <evidencia>
-- Deja la instancia EXACTAMENTE como estaba (cada cambio se deshace al final de su bloque).
WHENEVER SQLERROR CONTINUE
SET LINESIZE 160 PAGESIZE 100 FEEDBACK OFF
COLUMN name FORMAT A16
COLUMN en_memoria FORMAT A12
COLUMN en_spfile FORMAT A16
COLUMN contenedor FORMAT A10
COLUMN update_comment FORMAT A40
PROMPT
PROMPT ===== 1. SCOPE=MEMORY: cambia ya, se pierde al reiniciar =====
ALTER SYSTEM SET open_cursors = 400 SCOPE = MEMORY;
SELECT p.name, p.value AS en_memoria, NVL(s.value, '(sin valor)') AS en_spfile
  FROM v$parameter p JOIN v$spparameter s ON s.name = p.name
 WHERE p.name = 'open_cursors';
PROMPT
PROMPT ===== 2. SCOPE=BOTH con comentario: cambia ya y sobrevive al reinicio (queda en el SPFILE) =====
ALTER SYSTEM SET open_cursors = 500 COMMENT = 'Lab4: prueba SCOPE=BOTH' SCOPE = BOTH;
SELECT p.name, p.value AS en_memoria, s.value AS en_spfile, p.update_comment
  FROM v$parameter p JOIN v$spparameter s ON s.name = p.name
 WHERE p.name = 'open_cursors';
PROMPT -- Deshacer: volver al valor original en memoria y en el SPFILE
ALTER SYSTEM SET open_cursors = 300 COMMENT = '' SCOPE = BOTH;
PROMPT
PROMPT ===== 3. Parámetro ESTÁTICO: en memoria no se puede (ORA-02095 esperado) =====
ALTER SYSTEM SET db_files = 300 SCOPE = MEMORY;
PROMPT -- ... pero sí en el SPFILE: queda PENDIENTE hasta el próximo arranque
ALTER SYSTEM SET db_files = 300 SCOPE = SPFILE;
SELECT p.name, p.value AS en_memoria, s.value AS en_spfile
  FROM v$parameter p JOIN v$spparameter s ON s.name = p.name
 WHERE p.name = 'db_files';
PROMPT -- Deshacer con RESET: borra la línea del SPFILE y el parámetro vuelve a su valor por defecto
ALTER SYSTEM RESET db_files SCOPE = SPFILE;
SELECT p.name, p.value AS en_memoria, NVL(s.value, '(no especificado)') AS en_spfile
  FROM v$parameter p JOIN v$spparameter s ON s.name = p.name
 WHERE p.name = 'db_files';
PROMPT
PROMPT ===== 4. Dos casos que el examen adora =====
PROMPT -- PROCESSES fija cuántos procesos puede tener la instancia: cambio solo con reinicio (ORA-02095 esperado)
ALTER SYSTEM SET processes = 250 SCOPE = MEMORY;
PROMPT -- MEMORY_SIZE (26ai) solo es dinámico si la instancia ARRANCÓ con él (ORA-62352 esperado)
ALTER SYSTEM SET memory_size = 1600M SCOPE = MEMORY;
PROMPT
PROMPT ===== 5. Parámetros a nivel de PDB =====
ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER SYSTEM SET open_cursors = 350 SCOPE = MEMORY;
SELECT SYS_CONTEXT('USERENV', 'CON_NAME') AS contenedor, name, value AS en_memoria
  FROM v$parameter WHERE name = 'open_cursors';
PROMPT -- Un parámetro de instancia no se puede tocar desde una PDB (ORA-65040 esperado)
ALTER SYSTEM SET processes = 300 SCOPE = SPFILE;
PROMPT -- Deshacer en la PDB: heredar otra vez el valor del CDB
ALTER SYSTEM RESET open_cursors SCOPE = MEMORY;
ALTER SESSION SET CONTAINER = CDB$ROOT;
SELECT SYS_CONTEXT('USERENV', 'CON_NAME') AS contenedor, name, value AS en_memoria
  FROM v$parameter WHERE name = 'open_cursors';
PROMPT
PROMPT ===== 6. Nivel SESIÓN: solo afecta a esta conexión =====
ALTER SESSION SET nls_date_format = 'YYYY-MM-DD HH24:MI:SS';
SELECT SYSDATE AS ahora_con_formato_de_sesion FROM dual;
PROMPT
PROMPT ===== 7. Copia legible del SPFILE (PFILE) para versionar la configuración =====
CREATE PFILE = '/tmp/initFREE_lab4.ora' FROM SPFILE;
CREATE PFILE = '/tmp/initFREE_lab4_memoria.ora' FROM MEMORY;
PROMPT PFILE creados en /tmp del contenedor (07-copiar-pfile.sh los trae al repositorio)
EXIT
