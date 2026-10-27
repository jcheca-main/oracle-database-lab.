-- scripts/lab5/03-tipos-indice.sql — cada tipo de índice frente a la consulta de TiendaSur para la que existe (Actividad 3.2)
-- Se ejecuta como SYSDBA: bash scripts/ops/sysdba.sh <este archivo> <evidencia>
-- Todo lo que crea lo BORRA al final: aquí se experimenta. Lo que se decida conservar entra por migración (V005, Parte G).
WHENEVER SQLERROR EXIT FAILURE
SET LINESIZE 250 PAGESIZE 100 FEEDBACK OFF VERIFY OFF TAB OFF
COLUMN index_name FORMAT A22
COLUMN index_type FORMAT A22
ALTER SESSION SET CONTAINER = FREEPDB1;
SET SERVEROUTPUT ON FORMAT WRAPPED
-- Experimento PREVIO a V005: si V005 ya está aplicada (IX_PED_CLIENTE ya no existe) se detiene, porque su limpieza
-- borraría índices que V005 creó. Si una ejecución anterior falló a medias, se borran sus restos para poder repetirlo.
DECLARE
  n NUMBER;
  PROCEDURE quitar(p_ddl VARCHAR2) IS BEGIN EXECUTE IMMEDIATE p_ddl; EXCEPTION WHEN OTHERS THEN NULL; END;
BEGIN
  SELECT COUNT(*) INTO n FROM dba_indexes WHERE owner = 'TIENDASUR' AND index_name = 'IX_PED_CLIENTE';
  IF n = 0 THEN
    RAISE_APPLICATION_ERROR(-20005, 'V005 ya está aplicada: este experimento es anterior. Para repetirlo, restaura la copia lab4-final y vuelve a la Parte B');
  END IF;
  quitar('DROP INDEX tiendasur.ux_cli_dni');
  quitar('DROP INDEX tiendasur.ix_ped_cli_fec');
  quitar('DROP INDEX tiendasur.ix_ped_cli_fec_cub');
  quitar('DROP INDEX tiendasur.ix_cli_upper_email');
  quitar('DROP INDEX tiendasur.ix_ped_est_fec');
  quitar('DROP INDEX tiendasur.ix_ped_pendientes');
  quitar('ALTER TABLE tiendasur.pedido DROP COLUMN fecha_pendiente');
  quitar('DROP TABLE tiendasur.venta_hecho PURGE');
  quitar('DROP TABLE tiendasur.sesion_heap PURGE');
  quitar('DROP TABLE tiendasur.sesion_iot PURGE');
  quitar('DROP TABLE tiendasur.sesion_hash');
  quitar('DROP CLUSTER tiendasur.cl_sesion');
END;
/
COLUMN dni NEW_VALUE dni NOPRINT
SELECT dni FROM tiendasur.cliente WHERE id_cliente = 4711;
PROMPT
PROMPT ===== 1. ÚNICO (Q13, verificación de identidad): buscar Y garantizar que no hay dos DNI iguales =====
EXEC lab_tools.medir.consulta('Q13 sin índice', q'[SELECT id_cliente, nombre, apellidos FROM tiendasur.cliente WHERE dni = '&dni']')
CREATE UNIQUE INDEX tiendasur.ux_cli_dni ON tiendasur.cliente (dni);
EXEC lab_tools.medir.consulta('Q13 con UNIQUE (dni)', q'[SELECT id_cliente, nombre, apellidos FROM tiendasur.cliente WHERE dni = '&dni']')
PROMPT -- Y ahora la base de datos, no la aplicación, impide el duplicado (ORA-00001 esperado):
WHENEVER SQLERROR CONTINUE
INSERT INTO tiendasur.cliente VALUES (999999, '&dni', 'otro@tiendasur.es', 'X', 'Y', NULL, 'ES', 'Lorca', SYSDATE);
WHENEVER SQLERROR EXIT FAILURE
PROMPT
PROMPT ===== 2. COMPUESTO y regla del prefijo izquierdo (Q6, clientes de Lorca) con IX_CLI_PAIS_CIUDAD (pais, ciudad) =====
EXEC lab_tools.medir.consulta('Q6 solo ciudad', q'[SELECT id_cliente, nombre, apellidos FROM tiendasur.cliente WHERE ciudad = 'Lorca']')
EXEC lab_tools.medir.consulta('Q6 pais + ciudad', q'[SELECT id_cliente, nombre, apellidos FROM tiendasur.cliente WHERE pais = 'ES' AND ciudad = 'Lorca']')
PROMPT (Sin la primera columna, Oracle puede hacer SKIP SCAN: una búsqueda por cada país (40). Funciona, pero es un parche, no un diseño)
PROMPT
PROMPT ===== 3. COMPUESTO y CUBRIENTE (Q7, la consulta más frecuente: historial del cliente en la app) =====
DEFINE q7 = "SELECT id_pedido, fecha_pedido, importe, estado FROM tiendasur.pedido WHERE id_cliente = 4711 AND fecha_pedido >= SYSDATE - 365 ORDER BY fecha_pedido DESC"
EXEC lab_tools.medir.consulta('Q7 con ix_ped_cliente', '&q7')
CREATE INDEX tiendasur.ix_ped_cli_fec ON tiendasur.pedido (id_cliente, fecha_pedido);
EXEC lab_tools.medir.consulta('Q7 (id_cliente, fecha)', '&q7')
CREATE INDEX tiendasur.ix_ped_cli_fec_cub ON tiendasur.pedido (id_cliente, fecha_pedido, importe, estado, id_pedido);
EXEC lab_tools.medir.consulta('Q7 cubriente', '&q7')
PROMPT (Igualdad primero, rango después: el índice devuelve las filas YA ORDENADAS (sin SORT). Cubriente: ni siquiera toca la tabla)
PROMPT (Oracle no tiene INCLUDE como SQL Server o PostgreSQL: las columnas "de regalo" se añaden al final de la clave)
PROMPT
PROMPT ===== 4. FUNCIONAL (Q1, inicio de sesión con UPPER(email)) =====
EXEC lab_tools.medir.consulta('Q1 UPPER(email) tal cual', q'[SELECT id_cliente, nombre FROM tiendasur.cliente WHERE UPPER(email) = UPPER('Cliente4711@TiendaSur.es')]')
CREATE INDEX tiendasur.ix_cli_upper_email ON tiendasur.cliente (UPPER(email));
EXEC lab_tools.medir.consulta('Q1 con índice funcional', q'[SELECT id_cliente, nombre FROM tiendasur.cliente WHERE UPPER(email) = UPPER('Cliente4711@TiendaSur.es')]')
PROMPT (Funciona, pero es un índice más que mantener. Como el email se guarda en minúsculas, lo profesional es REESCRIBIR: Parte F)
PROMPT
PROMPT ===== 5. PARCIAL a la manera de Oracle (Q12, pedidos pendientes): una columna virtual que es NULL salvo en 'P' =====
CREATE INDEX tiendasur.ix_ped_est_fec ON tiendasur.pedido (estado, fecha_pedido);
ALTER TABLE tiendasur.pedido ADD (fecha_pendiente AS (CASE WHEN estado = 'P' THEN fecha_pedido END));
CREATE INDEX tiendasur.ix_ped_pendientes ON tiendasur.pedido (fecha_pendiente);
EXEC lab_tools.medir.consulta('Q12 (estado, fecha)', q'[SELECT id_pedido, id_cliente, fecha_pedido FROM tiendasur.pedido WHERE estado = 'P' ORDER BY fecha_pedido]')
EXEC lab_tools.medir.consulta('Q12 parcial', q'[SELECT id_pedido, id_cliente, fecha_pedido FROM tiendasur.pedido WHERE fecha_pendiente IS NOT NULL ORDER BY fecha_pendiente]')
SELECT index_name, leaf_blocks AS hojas, num_rows AS entradas FROM dba_indexes
 WHERE owner = 'TIENDASUR' AND index_name IN ('IX_PED_EST_FEC', 'IX_PED_PENDIENTES') ORDER BY index_name;
PROMPT (Oracle no guarda en un B-tree las claves totalmente NULL: el índice "parcial" solo tiene el 2 % de las filas. 150 UPDATE/s de estado
PROMPT  tocan un índice diminuto en lugar de uno de un millón de entradas)
PROMPT
PROMPT ===== 6. BITMAP (Q14, almacén de datos: los analistas combinan filtros a su gusto) =====
CREATE TABLE tiendasur.venta_hecho NOLOGGING AS
SELECT ROWNUM AS id_venta, 2021 + MOD(ORA_HASH(ROWNUM, 4294967295, 21), 5) AS anio,
       'R' || MOD(ORA_HASH(ROWNUM, 4294967295, 22), 6) AS region,
       SUBSTR('WAT', MOD(ORA_HASH(ROWNUM, 4294967295, 23), 3) + 1, 1) AS canal,
       'Cat' || MOD(ORA_HASH(ROWNUM, 4294967295, 24), 25) AS categoria,
       ROUND(MOD(ORA_HASH(ROWNUM, 4294967295, 25), 50000) / 100, 2) AS importe
  FROM (SELECT 1 FROM dual CONNECT BY LEVEL <= 1000), (SELECT 1 FROM dual CONNECT BY LEVEL <= 1000);
CREATE INDEX tiendasur.ix_vh_region_btree ON tiendasur.venta_hecho (region);
EXEC DBMS_STATS.GATHER_TABLE_STATS('TIENDASUR', 'VENTA_HECHO')
EXEC lab_tools.medir.consulta('Q14 sin bitmaps', q'[SELECT SUM(importe) FROM tiendasur.venta_hecho WHERE region = 'R1' AND canal = 'W' AND categoria = 'Cat7' AND anio = 2025]')
DROP INDEX tiendasur.ix_vh_region_btree;
CREATE BITMAP INDEX tiendasur.bx_vh_anio ON tiendasur.venta_hecho (anio);
CREATE BITMAP INDEX tiendasur.bx_vh_region ON tiendasur.venta_hecho (region);
CREATE BITMAP INDEX tiendasur.bx_vh_canal ON tiendasur.venta_hecho (canal);
CREATE BITMAP INDEX tiendasur.bx_vh_categoria ON tiendasur.venta_hecho (categoria);
EXEC lab_tools.medir.consulta('Q14 con 4 bitmaps', q'[SELECT SUM(importe) FROM tiendasur.venta_hecho WHERE region = 'R1' AND canal = 'W' AND categoria = 'Cat7' AND anio = 2025]')
CREATE INDEX tiendasur.ix_vh_region_btree ON tiendasur.venta_hecho (region) INVISIBLE;
SELECT index_name, index_type, leaf_blocks AS hojas, distinct_keys AS claves FROM dba_indexes
 WHERE owner = 'TIENDASUR' AND table_name = 'VENTA_HECHO' ORDER BY index_type, index_name;
PROMPT (El bitmap de region ocupa una fracción del B-tree equivalente. Pero cada bitmap bloquea rangos enteros de filas al modificarlas:
PROMPT  en OLTP con escrituras concurrentes es un desastre; en un almacén que se carga de noche, ideal)
PROMPT
PROMPT ===== 7. HASH e IOT (Q15, validar una sesión por su token: 40 000 por segundo) =====
CREATE TABLE tiendasur.sesion_heap (token CHAR(64) PRIMARY KEY, id_cliente NUMBER, caduca TIMESTAMP);
CREATE TABLE tiendasur.sesion_iot (token CHAR(64) PRIMARY KEY, id_cliente NUMBER, caduca TIMESTAMP) ORGANIZATION INDEX;
CREATE CLUSTER tiendasur.cl_sesion (token CHAR(64)) SIZE 100 SINGLE TABLE HASHKEYS 200000;
CREATE TABLE tiendasur.sesion_hash (token CHAR(64), id_cliente NUMBER, caduca TIMESTAMP) CLUSTER tiendasur.cl_sesion (token);
INSERT INTO tiendasur.sesion_heap SELECT STANDARD_HASH(TO_CHAR(LEVEL), 'SHA256'), MOD(LEVEL, 100000) + 1, SYSTIMESTAMP + MOD(LEVEL, 120) / 1440
  FROM dual CONNECT BY LEVEL <= 200000;
INSERT INTO tiendasur.sesion_iot SELECT * FROM tiendasur.sesion_heap;
INSERT INTO tiendasur.sesion_hash SELECT * FROM tiendasur.sesion_heap;
COMMIT;
COLUMN tok NEW_VALUE tok NOPRINT
SELECT RAWTOHEX(STANDARD_HASH('4711', 'SHA256')) AS tok FROM dual;
EXEC lab_tools.medir.consulta('Q15 montículo + PK', q'[SELECT id_cliente FROM tiendasur.sesion_heap WHERE token = '&tok']')
EXEC lab_tools.medir.consulta('Q15 IOT', q'[SELECT id_cliente FROM tiendasur.sesion_iot WHERE token = '&tok']')
EXEC lab_tools.medir.consulta('Q15 clúster hash', q'[SELECT id_cliente FROM tiendasur.sesion_hash WHERE token = '&tok']')
EXEC lab_tools.medir.consulta('Q15 limpieza en hash', q'[SELECT COUNT(*) FROM tiendasur.sesion_hash WHERE caduca < SYSTIMESTAMP + 1/1440]')
PROMPT (Hash: la clave se convierte en la dirección del bloque, 1 lectura. Pero no sirve para rangos: la limpieza recorre la tabla entera.
PROMPT  IOT: la tabla ES el índice, ahorra el salto a la tabla. Montículo + PK: la opción por defecto, buena casi siempre)
PROMPT
PROMPT ===== 8. Ningún índice es gratis: lo que ocupa cada uno =====
SELECT s.segment_name AS index_name, i.index_type, ROUND(s.bytes / 1048576, 1) AS mb, i.leaf_blocks AS hojas
  FROM dba_segments s JOIN dba_indexes i ON i.owner = s.owner AND i.index_name = s.segment_name
 WHERE s.owner = 'TIENDASUR' AND i.table_name IN ('CLIENTE', 'PEDIDO') ORDER BY s.bytes DESC;
PROMPT
PROMPT ===== 9. Limpieza: el banco vuelve a su estado de partida (las decisiones se aplican por migración, V005) =====
DROP INDEX tiendasur.ux_cli_dni;
DROP INDEX tiendasur.ix_ped_cli_fec;
DROP INDEX tiendasur.ix_ped_cli_fec_cub;
DROP INDEX tiendasur.ix_cli_upper_email;
DROP INDEX tiendasur.ix_ped_est_fec;
DROP INDEX tiendasur.ix_ped_pendientes;
ALTER TABLE tiendasur.pedido DROP COLUMN fecha_pendiente;
DROP TABLE tiendasur.venta_hecho PURGE;
DROP TABLE tiendasur.sesion_heap PURGE;
DROP TABLE tiendasur.sesion_iot PURGE;
DROP TABLE tiendasur.sesion_hash;
DROP CLUSTER tiendasur.cl_sesion;
SELECT COUNT(*) AS indices_tiendasur FROM dba_indexes WHERE owner = 'TIENDASUR';
EXIT
