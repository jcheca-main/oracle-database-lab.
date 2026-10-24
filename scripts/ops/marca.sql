-- scripts/ops/marca.sql — define &marca con la hora UTC (AAAAMMDDTHHMMSSZ) para nombrar evidencias desde SQLcl
SET TERMOUT OFF
COLUMN marca_utc NEW_VALUE marca NOPRINT
SELECT TO_CHAR(SYS_EXTRACT_UTC(SYSTIMESTAMP), 'YYYYMMDD"T"HH24MISS"Z"') AS marca_utc FROM dual;
SET TERMOUT ON
