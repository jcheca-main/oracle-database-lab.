-- scripts/lab5/06-propuesta-companero.sql — Q16: los cinco índices que propone un compañero "para que todo vaya rápido"
-- Se crean para MEDIR lo que cuestan; 06-protocolo.sql los audita y 06-indices.sh los borra antes de aplicar V005.
WHENEVER SQLERROR EXIT FAILURE
SET FEEDBACK OFF
ALTER SESSION SET CONTAINER = FREEPDB1;
-- Restos de una ejecución anterior que falló a medias (06-indices.sh ya comprobó que V005 no está aplicada)
BEGIN
  FOR i IN (SELECT index_name FROM dba_indexes WHERE owner = 'TIENDASUR'
               AND index_name IN ('IX_PED_ESTADO', 'IX_PED_CANAL', 'IX_PED_CLI_FEC', 'IX_PED_FEC_CLI', 'IX_PED_CP')) LOOP
    EXECUTE IMMEDIATE 'DROP INDEX tiendasur.' || i.index_name;
  END LOOP;
  EXECUTE IMMEDIATE 'ALTER INDEX tiendasur.ix_ped_importe VISIBLE';
END;
/
CREATE INDEX tiendasur.ix_ped_estado  ON tiendasur.pedido (estado);
CREATE INDEX tiendasur.ix_ped_canal   ON tiendasur.pedido (canal);
CREATE INDEX tiendasur.ix_ped_cli_fec ON tiendasur.pedido (id_cliente, fecha_pedido);
CREATE INDEX tiendasur.ix_ped_fec_cli ON tiendasur.pedido (fecha_pedido, id_cliente);
CREATE INDEX tiendasur.ix_ped_cp      ON tiendasur.pedido (codigo_postal);
PROMPT Propuesta del compañero creada: 5 índices más sobre PEDIDO
EXIT
