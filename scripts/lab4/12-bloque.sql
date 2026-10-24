-- scripts/lab4/12-bloque.sql — del tablespace a la fila: segmento, extensión, bloque, fila y su volcado real
-- Se lanza con scripts/lab4/12-bloque.sh, que además copia la traza completa del volcado a la evidencia.
WHENEVER SQLERROR EXIT FAILURE
SET LINESIZE 170 PAGESIZE 100 FEEDBACK OFF VERIFY OFF
COLUMN tablespace_name FORMAT A14
COLUMN segment_name FORMAT A26
COLUMN segment_type FORMAT A10
COLUMN owner FORMAT A16
COLUMN file_name FORMAT A50
COLUMN columna FORMAT A20
COLUMN bytes_internos FORMAT A64
COLUMN payload FORMAT A110
COLUMN nivel FORMAT A34
ALTER SESSION SET CONTAINER = FREEPDB1;
PROMPT
PROMPT ===== 1. Los tablespaces de la PDB: tipo, gestión de extensiones y de espacio en segmentos =====
SELECT tablespace_name, contents, bigfile, extent_management AS extents, allocation_type AS asignacion,
       segment_space_management AS ssm, block_size
  FROM dba_tablespaces ORDER BY tablespace_name;
PROMPT
PROMPT ===== 2. Segmentos de ADMIN_ACADEMIA (tablas, índices, LOB...) =====
SELECT segment_name, segment_type, tablespace_name, extents, blocks, ROUND(bytes / 1024) AS kb
  FROM dba_segments WHERE owner = 'ADMIN_ACADEMIA' ORDER BY bytes DESC;
PROMPT
PROMPT ===== 3. Extensiones de ACA_ESTUDIANTES (AUTOALLOCATE: 64 KB, después 1 MB...) =====
SELECT extent_id, file_id, block_id, blocks, ROUND(bytes / 1024) AS kb
  FROM dba_extents WHERE owner = 'ADMIN_ACADEMIA' AND segment_name = 'ACA_ESTUDIANTES' ORDER BY extent_id;
PROMPT
PROMPT ===== 4. La fila 101: su ROWID y su dirección física (DBMS_ROWID) =====
PROMPT (TBS_ACADEMIA es BIGFILE -predeterminado desde 23ai-: un solo archivo, relative_fno 1024;
PROMPT  por eso el bloque se decodifica con 'BIGFILE' y el archivo con ROWID_TO_ABSOLUTE_FNO)
COLUMN f NEW_VALUE f NOPRINT
COLUMN b NEW_VALUE b NOPRINT
COLUMN s NEW_VALUE s NOPRINT
SELECT e.estudiante_id, e.estado, ROWIDTOCHAR(e.ROWID) AS rowid_fila,
       DBMS_ROWID.ROWID_OBJECT(e.ROWID) AS data_object_id,
       DBMS_ROWID.ROWID_TO_ABSOLUTE_FNO(e.ROWID, 'ADMIN_ACADEMIA', 'ACA_ESTUDIANTES') AS archivo,
       DBMS_ROWID.ROWID_BLOCK_NUMBER(e.ROWID, 'BIGFILE') AS bloque,
       DBMS_ROWID.ROWID_ROW_NUMBER(e.ROWID) AS fila_en_bloque,
       TO_CHAR(DBMS_ROWID.ROWID_TO_ABSOLUTE_FNO(e.ROWID, 'ADMIN_ACADEMIA', 'ACA_ESTUDIANTES')) AS f,
       TO_CHAR(DBMS_ROWID.ROWID_BLOCK_NUMBER(e.ROWID, 'BIGFILE')) AS b, TO_CHAR(DBMS_ROWID.ROWID_ROW_NUMBER(e.ROWID)) AS s
  FROM admin_academia.aca_estudiantes e WHERE e.estudiante_id = 101;
PROMPT -- ¿Qué archivo del disco es ese número? ¿Y qué objeto es ese data_object_id?
SELECT file_id, relative_fno, file_name FROM dba_data_files
 WHERE file_id = (SELECT DBMS_ROWID.ROWID_TO_ABSOLUTE_FNO(ROWID, 'ADMIN_ACADEMIA', 'ACA_ESTUDIANTES')
                    FROM admin_academia.aca_estudiantes WHERE estudiante_id = 101);
COLUMN object_name FORMAT A16
SELECT owner, object_name, object_type, data_object_id FROM dba_objects
 WHERE data_object_id = (SELECT DBMS_ROWID.ROWID_OBJECT(ROWID) FROM admin_academia.aca_estudiantes WHERE estudiante_id = 101);
PROMPT
PROMPT ===== 5. Anatomía de la FILA 101 byte a byte: DUMP() muestra cómo guarda Oracle cada valor =====
PROMPT (Typ=2 NUMBER en formato interno de base 100 · Typ=1 VARCHAR2 en ASCII · Typ=180 TIMESTAMP · Len = bytes)
SELECT 'ESTUDIANTE_ID' AS columna, DUMP(estudiante_id, 16) AS bytes_internos FROM admin_academia.aca_estudiantes WHERE estudiante_id = 101
UNION ALL SELECT 'DNI', DUMP(dni, 16) FROM admin_academia.aca_estudiantes WHERE estudiante_id = 101
UNION ALL SELECT 'NOMBRES', DUMP(nombres, 16) FROM admin_academia.aca_estudiantes WHERE estudiante_id = 101
UNION ALL SELECT 'ESTADO', DUMP(estado, 16) FROM admin_academia.aca_estudiantes WHERE estudiante_id = 101
UNION ALL SELECT 'FECHA_REGISTRO', DUMP(fecha_registro, 16) FROM admin_academia.aca_estudiantes WHERE estudiante_id = 101;
PROMPT -- Tamaño de la fila: suma de VSIZE de sus columnas frente a AVG_ROW_LEN de las estadísticas
SELECT VSIZE(estudiante_id) + VSIZE(dni) + VSIZE(nombres) + VSIZE(apellidos) + VSIZE(email_institucional)
       + NVL(VSIZE(estado), 0) + VSIZE(fecha_registro) AS bytes_de_datos_fila_101,
       (SELECT avg_row_len FROM dba_tables WHERE owner = 'ADMIN_ACADEMIA' AND table_name = 'ACA_ESTUDIANTES') AS avg_row_len
  FROM admin_academia.aca_estudiantes WHERE estudiante_id = 101;
PROMPT
PROMPT ===== 6. ¿Cómo de llenos están los bloques de la tabla? (DBMS_SPACE.SPACE_USAGE, tablespaces ASSM) =====
SET SERVEROUTPUT ON
DECLARE
  unf NUMBER; unfb NUMBER; fs1 NUMBER; fs1b NUMBER; fs2 NUMBER; fs2b NUMBER;
  fs3 NUMBER; fs3b NUMBER; fs4 NUMBER; fs4b NUMBER; llenos NUMBER; llenosb NUMBER;
  PROCEDURE barra(p_txt VARCHAR2, p_n NUMBER) IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE(RPAD(p_txt, 30) || LPAD(p_n, 5) || '  ' || RPAD('#', CEIL(p_n / 4), '#'));
  END;
BEGIN
  DBMS_SPACE.SPACE_USAGE('ADMIN_ACADEMIA', 'ACA_ESTUDIANTES', 'TABLE', unf, unfb, fs1, fs1b, fs2, fs2b,
                         fs3, fs3b, fs4, fs4b, llenos, llenosb);
  barra('llenos (FULL)', llenos);
  barra('0-25 % libre (FS1)', fs1);
  barra('25-50 % libre (FS2)', fs2);
  barra('50-75 % libre (FS3)', fs3);
  barra('75-100 % libre (FS4)', fs4);
  barra('sin formatear (bajo la HWM)', unf);
END;
/
PROMPT
PROMPT ===== 7. Volcado REAL del bloque &b del archivo &f (ALTER SYSTEM DUMP DATAFILE ... BLOCK ...) =====
ALTER SESSION SET tracefile_identifier = 'lab4_bloque';
ALTER SYSTEM DUMP DATAFILE &f BLOCK &b;
COLUMN tf NEW_VALUE tf NOPRINT
SELECT SUBSTR(value, INSTR(value, '/', -1) + 1) AS tf FROM v$diag_info WHERE name = 'Default Trace File';
PROMPT Traza: &tf (12-bloque.sh la copia completa a la evidencia)
SET PAGESIZE 0
WITH t AS (SELECT line_number AS n, payload FROM v$diag_trace_file_contents WHERE trace_filename = '&tf'),
     m AS (SELECT MIN(CASE WHEN payload LIKE 'Block header dump%' THEN n END) AS cab,
                  MIN(CASE WHEN payload LIKE 'data_block_dump%' THEN n END) AS dat,
                  MIN(CASE WHEN payload LIKE 'tab 0, row &s,%' THEN n END) AS fil
             FROM t)
SELECT CASE WHEN t.n = m.cab THEN CHR(10) || '--- [A] CABECERA DEL BLOQUE Y LISTA DE TRANSACCIONES (ITL) ---' || CHR(10)
            WHEN t.n = m.dat THEN CHR(10) || '--- [B] CABECERA DE DATOS Y DIRECTORIO DE FILAS (slot array) ---' || CHR(10)
            WHEN t.n = m.fil THEN CHR(10) || '--- [C] LA FILA &s (estudiante 101), columna a columna ---' || CHR(10) END
       || RTRIM(t.payload, CHR(10)) AS payload
  FROM t, m
 WHERE t.n BETWEEN m.cab AND m.cab + 9
    OR t.n BETWEEN m.dat AND m.dat + 21
    OR t.n BETWEEN m.fil AND m.fil + 8
 ORDER BY t.n;
EXIT
