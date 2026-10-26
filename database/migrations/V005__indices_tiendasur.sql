-- database/migrations/V005__indices_tiendasur.sql
-- El diseño de índices de TiendaSur que sale del protocolo de cinco preguntas (Lab 5, Parte G; Actividad 3.2):
--   + ux_cli_dni          Q13 (500/s): busca por DNI y además GARANTIZA que no se repite (antes lo controlaba la aplicación)
--   + ix_ped_cli_fec_cub  Q7 (2000/s, la más frecuente): igualdad, rango y ORDER BY sin tocar la tabla. Empieza por id_cliente:
--                         sigue cubriendo la clave ajena, así que ix_ped_cliente sobra
--   - ix_ped_cliente      redundante: es prefijo de ix_ped_cli_fec_cub
--   + ix_ped_pendientes   Q12 (cada 30 s): índice parcial (solo el 2 % de filas en 'P') sobre una columna virtual
--   + ix_ped_cp           Q3 (50/s) una vez reescrita con '30001': 0,01 % de filas por código postal, muy por debajo del umbral
--   - ix_ped_importe      cero usos en la observación (MONITORING USAGE) y ya probado como INVISIBLE
--   = pk_pedido, ix_ped_fecha (Q2, Q8, Q9), pk_cliente, ux_cli_email (Q1 reescrita), ix_cli_pais_ciudad (Q6, skip scan aceptable)
-- Q1, Q2, Q3 y Q11 se arreglan REESCRIBIENDO la consulta (sargabilidad), no con índices. Q10 y Q11: el recorrido completo es lo correcto.
-- Idempotente: si ux_cli_dni ya existe, no hace nada.
SET FEEDBACK ON
ALTER SESSION SET CONTAINER = FREEPDB1;
WHENEVER SQLERROR EXIT SUCCESS
DECLARE n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM dba_indexes WHERE owner = 'TIENDASUR' AND index_name = 'UX_CLI_DNI';
  IF n > 0 THEN RAISE_APPLICATION_ERROR(-20005, 'V005 ya aplicada: UX_CLI_DNI existe, no se hace nada'); END IF;
END;
/
WHENEVER SQLERROR EXIT SQL.SQLCODE
CREATE UNIQUE INDEX tiendasur.ux_cli_dni ON tiendasur.cliente (dni) ONLINE;
CREATE INDEX tiendasur.ix_ped_cli_fec_cub ON tiendasur.pedido (id_cliente, fecha_pedido, importe, estado, id_pedido) ONLINE;
DROP INDEX tiendasur.ix_ped_cliente;
ALTER TABLE tiendasur.pedido ADD (fecha_pendiente AS (CASE WHEN estado = 'P' THEN fecha_pedido END));
CREATE INDEX tiendasur.ix_ped_pendientes ON tiendasur.pedido (fecha_pendiente) ONLINE;
CREATE INDEX tiendasur.ix_ped_cp ON tiendasur.pedido (codigo_postal) ONLINE;
DROP INDEX tiendasur.ix_ped_importe;
SET LINESIZE 150 PAGESIZE 50
COLUMN table_name FORMAT A8
COLUMN index_name FORMAT A20
SELECT table_name, index_name, uniqueness, visibility FROM dba_indexes WHERE owner = 'TIENDASUR' ORDER BY table_name, index_name;
EXIT
