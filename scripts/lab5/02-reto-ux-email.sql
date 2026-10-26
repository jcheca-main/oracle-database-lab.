-- scripts/lab5/02-reto-ux-email.sql
-- Reto profesional de la Parte C: comparar la altura calculada a mano de UX_CLI_EMAIL con la medida.
-- Asumiendo 30 bytes/entrada de hoja y fo_max 543 (el de IX_PED_CLIENTE):
--   cap_hoja = floor(7996/30) = 266; hojas = ceil(100000/266/0.9) = 418; altura = 1+ceil(log_543(418)) = 2
-- La medida real dira cuantos bytes ocupa de verdad cada entrada de hoja (email es ancho).
WHENEVER SQLERROR EXIT FAILURE
ALTER SESSION SET CONTAINER = FREEPDB1;
SET LINESIZE 170 PAGESIZE 100 FEEDBACK OFF
ANALYZE INDEX tiendasur.ux_cli_email VALIDATE STRUCTURE;
PROMPT === INDEX_STATS de UX_CLI_EMAIL (altura, hojas, bytes reales por entrada) ===
SELECT name AS index_name, height AS altura, lf_rows AS entradas, lf_blks AS hojas,
       ROUND(lf_rows_len / lf_rows, 1) AS bytes_por_entrada, lf_blk_len AS bytes_utiles_hoja
FROM index_stats;
EXIT
