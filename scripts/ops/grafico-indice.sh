#!/usr/bin/env bash
# scripts/ops/grafico-indice.sh — "radiografía" de un índice B-tree a partir de su treedump: ocupación de cada hoja,
# histograma de llenado y mapa de izquierda (claves bajas) a derecha (claves altas) para ver huecos y el patrón cola.
# Uso: bash scripts/ops/grafico-indice.sh <ESQUEMA> <INDICE> [archivo-de-evidencia]
#   p. ej. bash scripts/ops/grafico-indice.sh TIENDASUR IX_PED_CLIENTE "$EVID_LAB5/script/$(ts)_02-grafico.script.log"
# Solo lee: el treedump recorre el índice y escribe una traza; no bloquea la tabla. Seguro en laboratorio y en producción.
set -euo pipefail
source scripts/deployment/env/00-config.sh
OWNER="${1:?Uso: grafico-indice.sh <ESQUEMA> <INDICE> [evidencia]}"; INDICE="${2:?Falta el nombre del índice}"
LOG="${3:-/dev/null}"
[ "$LOG" = /dev/null ] || mkdir -p "$(dirname "$LOG")"
OWNER="${OWNER^^}"; INDICE="${INDICE^^}"
[[ "$OWNER" =~ ^[A-Z][A-Z0-9_$#]*$ && "$INDICE" =~ ^[A-Z][A-Z0-9_$#]*$ ]] || { echo "Nombre no válido" >&2; exit 2; }
# Cada línea "leaf: 0x... bloque (k: row:N.R avs:A)" del treedump es una hoja: N entradas, R vivas (N-R borradas), A bytes libres
HOJAS="(SELECT ROW_NUMBER() OVER (ORDER BY line_number) AS pos,
        TO_NUMBER(REGEXP_SUBSTR(payload, 'row:([0-9]+)', 1, 1, NULL, 1)) AS nrow,
        TO_NUMBER(REGEXP_SUBSTR(payload, 'row:[0-9]+[.]([0-9]+)', 1, 1, NULL, 1)) AS rrow,
        TO_NUMBER(REGEXP_SUBSTR(payload, 'avs:([0-9]+)', 1, 1, NULL, 1)) AS avs
   FROM v\$diag_trace_file_contents WHERE trace_filename = '&tf' AND payload LIKE '%leaf: 0x%')"
# Ocupación VIVA de una hoja: el espacio usado, descontando la parte que son entradas borradas (nrow - rrow)
OCU="CASE WHEN nrow = 0 THEN 0 ELSE (7996 - avs) / 7996 * rrow / nrow END"
docker exec -i "$CONT_NAME" sqlplus -s -L / as sysdba <<SQL | tee "$LOG"
WHENEVER SQLERROR EXIT FAILURE
SET LINESIZE 150 PAGESIZE 100 FEEDBACK OFF VERIFY OFF TAB OFF
ALTER SESSION SET CONTAINER = FREEPDB1;
DECLARE n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM dba_indexes WHERE owner = '$OWNER' AND index_name = '$INDICE';
  IF n = 0 THEN RAISE_APPLICATION_ERROR(-20010, 'No existe el índice $OWNER.$INDICE en FREEPDB1 (¿se borró en una parte posterior, p. ej. V005?)'); END IF;
END;
/
COLUMN oid NEW_VALUE oid NOPRINT
SELECT TO_CHAR(object_id) AS oid FROM dba_objects WHERE owner = '$OWNER' AND object_name = '$INDICE' AND object_type = 'INDEX';
ALTER SESSION SET tracefile_identifier = 'grafico_$INDICE';
ALTER SESSION SET EVENTS 'immediate trace name treedump level &oid';
COLUMN tf NEW_VALUE tf NOPRINT
SELECT SUBSTR(value, INSTR(value, '/', -1) + 1) AS tf FROM v\$diag_info WHERE name = 'Default Trace File';
COLUMN ocupacion FORMAT A52
COLUMN mapa FORMAT A66
COLUMN rango FORMAT A9
PROMPT
PROMPT ===== $OWNER.$INDICE · resumen (hoja útil = 7996 bytes en bloque de 8 KB) =====
SELECT COUNT(*) AS hojas, SUM(rrow) AS entradas_vivas, SUM(nrow - rrow) AS entradas_borradas,
       ROUND(AVG(rrow)) AS media_entradas_por_hoja,
       ROUND(100 * AVG($OCU), 1) AS pct_ocupacion_viva, ROUND(100 * AVG((7996 - avs) / 7996), 1) AS pct_espacio_usado,
       SUM(CASE WHEN rrow = 0 THEN 1 ELSE 0 END) AS hojas_vacias,
       SUM(CASE WHEN $OCU < 0.5 THEN 1 ELSE 0 END) AS hojas_bajo_50pct
  FROM $HOJAS;
PROMPT
PROMPT ===== Histograma: cuántas hojas hay en cada tramo de llenado (solo entradas vivas) =====
SELECT LPAD(TRUNC(LEAST(99, 100 * $OCU) / 10) * 10, 3) || '-' || RPAD(TRUNC(LEAST(99, 100 * $OCU) / 10) * 10 + 9, 2) || ' %' AS rango,
       COUNT(*) AS hojas,
       RPAD('#', CEIL(50 * COUNT(*) / MAX(COUNT(*)) OVER ()), '#') AS ocupacion
  FROM $HOJAS
 GROUP BY TRUNC(LEAST(99, 100 * $OCU) / 10) ORDER BY TRUNC(LEAST(99, 100 * $OCU) / 10);
PROMPT
PROMPT ===== Mapa de izquierda (claves bajas) a derecha (claves altas): 64 tramos de hojas consecutivas =====
PROMPT  Leyenda por ocupación media del tramo:  ' ' <10 %   . <30 %   : <50 %   - <70 %   = <90 %   # >=90 %
SELECT '[' || LISTAGG(CASE WHEN o < 0.1 THEN ' ' WHEN o < 0.3 THEN '.' WHEN o < 0.5 THEN ':'
                           WHEN o < 0.7 THEN '-' WHEN o < 0.9 THEN '=' ELSE '#' END) WITHIN GROUP (ORDER BY t) || ']' AS mapa
  FROM (SELECT t, AVG($OCU) AS o
          FROM (SELECT NTILE(64) OVER (ORDER BY pos) AS t, nrow, rrow, avs FROM $HOJAS) GROUP BY t);
PROMPT  Pista para leer el mapa: si la izquierda está vacía y la derecha llena, es un PATRÓN COLA (se inserta por la derecha y se borra por la izquierda)
EXIT
SQL
