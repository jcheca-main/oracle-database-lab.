-- database/migrations/V004__banco_tiendasur.sql
-- Banco de pruebas de índices del Lab 5: TiendaSur, el escenario de la Actividad en clase 3.2 (Unidad 3), a escala 1/10 y 1/20:
--   cliente  100 000 filas (en la actividad, 1 000 000)      pedido  1 000 000 filas (en la actividad, 20 000 000)
-- Se conservan las proporciones que hacen interesante cada consulta Q1-Q16:
--   pais: 40 valores, 'ES' el 60 %       ciudad: 2000 valores, 'Lorca' 100 clientes      apellidos 'Gonz%': 2 %
--   estado: P 2 % (los más recientes) · E 5 % · C 90 % · D 3 %      canal W/A/T      codigo_postal VARCHAR2(5), 11 000 valores
--   id_pedido y fecha_pedido crecen juntos (correlación física BUENA); id_cliente es aleatorio (correlación MALA)
-- Los datos son deterministas (ORA_HASH, sin DBMS_RANDOM): todos los equipos obtienen las mismas cifras.
-- La historia acaba el día en que se aplica la migración, para que "el último mes" tenga filas.
-- Idempotente: si TIENDASUR ya existe, no hace nada.
SET FEEDBACK ON SERVEROUTPUT ON
ALTER SESSION SET CONTAINER = FREEPDB1;
WHENEVER SQLERROR EXIT SUCCESS
DECLARE n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM dba_users WHERE username = 'TIENDASUR';
  IF n > 0 THEN RAISE_APPLICATION_ERROR(-20004, 'V004 ya aplicada: TIENDASUR existe, no se hace nada'); END IF;
END;
/
WHENEVER SQLERROR EXIT SQL.SQLCODE
CREATE BIGFILE TABLESPACE tbs_tiendasur DATAFILE '/opt/oracle/oradata/FREE/FREEPDB1/tiendasur01.dbf'
  SIZE 256M AUTOEXTEND ON NEXT 64M MAXSIZE 2G;
CREATE USER tiendasur NO AUTHENTICATION DEFAULT TABLESPACE tbs_tiendasur QUOTA UNLIMITED ON tbs_tiendasur;
ALTER SESSION SET CURRENT_SCHEMA = tiendasur;

CREATE TABLE cliente (
  id_cliente  NUMBER(10)    NOT NULL CONSTRAINT pk_cliente PRIMARY KEY,
  dni         CHAR(9)       NOT NULL,
  email       VARCHAR2(120) NOT NULL,          -- el backend lo guarda siempre en minúsculas
  nombre      VARCHAR2(60)  NOT NULL,
  apellidos   VARCHAR2(80)  NOT NULL,
  telefono    VARCHAR2(15),
  pais        CHAR(2)       NOT NULL,
  ciudad      VARCHAR2(60)  NOT NULL,
  fecha_alta  DATE          NOT NULL
);
CREATE TABLE pedido (
  id_pedido     NUMBER(12)    NOT NULL CONSTRAINT pk_pedido PRIMARY KEY,
  id_cliente    NUMBER(10)    NOT NULL,
  fecha_pedido  TIMESTAMP(0)  NOT NULL,
  estado        CHAR(1)       NOT NULL CONSTRAINT ck_ped_estado CHECK (estado IN ('P', 'E', 'C', 'D')),
  importe       NUMBER(12,2)  NOT NULL,
  canal         CHAR(1)       NOT NULL,        -- 'W' web, 'A' app, 'T' tienda física
  codigo_postal VARCHAR2(5)   NOT NULL
);

-- Clientes: en orden de alta (id_cliente correlacionado con su posición física)
INSERT /*+ APPEND */ INTO cliente
SELECT n,
       LPAD(n, 8, '0') || SUBSTR('TRWAGMYFPDXBNJZSQVHLCKE', MOD(n, 23) + 1, 1),
       'cliente' || n || '@tiendasur.es',
       'Nombre' || MOD(ORA_HASH(n, 4294967295, 1), 500),
       CASE WHEN MOD(ORA_HASH(n, 4294967295, 2), 100) < 2
            THEN CASE MOD(n, 2) WHEN 0 THEN 'González' ELSE 'Gonzalo' END
            ELSE CASE MOD(ORA_HASH(n, 4294967295, 3), 12)
                   WHEN 0 THEN 'Martínez' WHEN 1 THEN 'López' WHEN 2 THEN 'Sánchez' WHEN 3 THEN 'Pérez'
                   WHEN 4 THEN 'García' WHEN 5 THEN 'Ruiz' WHEN 6 THEN 'Moreno' WHEN 7 THEN 'Navarro'
                   WHEN 8 THEN 'Fernández' WHEN 9 THEN 'Romero' WHEN 10 THEN 'Torres' ELSE 'Castillo' END END
       || ' ' || CASE MOD(ORA_HASH(n, 4294967295, 4), 16)
                   WHEN 0 THEN 'Gil' WHEN 1 THEN 'Ortiz' WHEN 2 THEN 'Rubio' WHEN 3 THEN 'Marín' WHEN 4 THEN 'Sanz' WHEN 5 THEN 'Iglesias'
                   WHEN 6 THEN 'Núñez' WHEN 7 THEN 'Medina' WHEN 8 THEN 'Garrido' WHEN 9 THEN 'Cortés' WHEN 10 THEN 'Castro'
                   WHEN 11 THEN 'Lozano' WHEN 12 THEN 'Vidal' WHEN 13 THEN 'Domínguez' WHEN 14 THEN 'Ramos' ELSE 'Méndez' END,
       '6' || LPAD(MOD(ORA_HASH(n, 4294967295, 5), 100000000), 8, '0'),
       CASE WHEN MOD(n, 1000) = 0 OR MOD(ORA_HASH(n, 4294967295, 6), 100) < 60 THEN 'ES'
            ELSE CHR(65 + MOD(ORA_HASH(n, 4294967295, 7), 13)) || CHR(65 + MOD(ORA_HASH(n, 4294967295, 8), 3)) END,
       CASE WHEN MOD(n, 1000) = 0 THEN 'Lorca' ELSE 'Ciudad' || LPAD(MOD(ORA_HASH(n, 4294967295, 9), 1999) + 1, 4, '0') END,
       DATE '2019-01-01' + TRUNC((n - 1) * (TRUNC(SYSDATE) - DATE '2019-01-01') / 100000)
  FROM (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= 100000)
 ORDER BY n;
COMMIT;

-- Pedidos: en orden de llegada (id_pedido y fecha_pedido crecen juntos); id_cliente al azar
INSERT /*+ APPEND */ INTO pedido
SELECT n,
       MOD(ORA_HASH(n, 4294967295, 11), 100000) + 1,
       CAST(TRUNC(SYSDATE) - 3 * 365 AS TIMESTAMP(0)) + NUMTODSINTERVAL(TRUNC((n - 1) * (3 * 365 * 86400 / 1000000)), 'SECOND'),
       CASE WHEN n > 980000 THEN 'P'                                       -- todo pedido nace en P: los más nuevos
            WHEN n > 930000 THEN 'E'
            WHEN MOD(ORA_HASH(n, 4294967295, 12), 100) < 3 THEN 'D'
            ELSE 'C' END,
       ROUND(5 + MOD(ORA_HASH(n, 4294967295, 13), 50000) / 100, 2),
       CASE WHEN MOD(ORA_HASH(n, 4294967295, 14), 100) < 55 THEN 'W'
            WHEN MOD(ORA_HASH(n, 4294967295, 14), 100) < 90 THEN 'A' ELSE 'T' END,
       TO_CHAR(25000 + MOD(ORA_HASH(n, 4294967295, 15), 11000))
  FROM (SELECT (a.k - 1) * 1000 + b.k AS n
          FROM (SELECT LEVEL AS k FROM dual CONNECT BY LEVEL <= 1000) a,
               (SELECT LEVEL AS k FROM dual CONNECT BY LEVEL <= 1000) b)
 ORDER BY n;
COMMIT;

-- Los índices que TiendaSur "hereda" (los mismos de la actividad)
CREATE UNIQUE INDEX ux_cli_email ON cliente (email);
CREATE INDEX ix_cli_pais_ciudad ON cliente (pais, ciudad);
CREATE INDEX ix_ped_cliente ON pedido (id_cliente);
CREATE INDEX ix_ped_fecha ON pedido (fecha_pedido);
CREATE INDEX ix_ped_importe ON pedido (importe);
ALTER TABLE pedido ADD CONSTRAINT fk_ped_cliente FOREIGN KEY (id_cliente) REFERENCES cliente;

-- Estadísticas con histograma en las columnas sesgadas: sin él, el optimizador creería que 'P' es el 25 % de los pedidos
BEGIN
  DBMS_STATS.GATHER_TABLE_STATS('TIENDASUR', 'CLIENTE', method_opt => 'FOR ALL COLUMNS SIZE 1 FOR COLUMNS SIZE 254 pais ciudad', cascade => TRUE);
  DBMS_STATS.GATHER_TABLE_STATS('TIENDASUR', 'PEDIDO', method_opt => 'FOR ALL COLUMNS SIZE 1 FOR COLUMNS SIZE 254 estado canal', cascade => TRUE);
END;
/
SET LINESIZE 150 PAGESIZE 50
COLUMN table_name FORMAT A10
SELECT table_name, num_rows, blocks, avg_row_len, ROUND(num_rows / blocks) AS bfr FROM dba_tables
 WHERE owner = 'TIENDASUR' ORDER BY table_name;
SELECT estado, COUNT(*) AS pedidos, ROUND(100 * RATIO_TO_REPORT(COUNT(*)) OVER (), 1) AS pct FROM pedido GROUP BY estado ORDER BY estado;
EXIT
