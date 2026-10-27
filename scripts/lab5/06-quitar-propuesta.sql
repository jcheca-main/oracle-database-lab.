-- scripts/lab5/06-quitar-propuesta.sql — se retira la propuesta del compañero tras auditarla (06-protocolo.sql)
WHENEVER SQLERROR EXIT FAILURE
SET FEEDBACK OFF
ALTER SESSION SET CONTAINER = FREEPDB1;
DROP INDEX tiendasur.ix_ped_estado;
DROP INDEX tiendasur.ix_ped_canal;
DROP INDEX tiendasur.ix_ped_cli_fec;
DROP INDEX tiendasur.ix_ped_fec_cli;
DROP INDEX tiendasur.ix_ped_cp;
ALTER INDEX tiendasur.ix_ped_importe VISIBLE;
PROMPT Propuesta del compañero retirada
EXIT
