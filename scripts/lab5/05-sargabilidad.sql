-- scripts/lab5/05-sargabilidad.sql — las reglas de oro de la sargabilidad, consulta rota frente a consulta reescrita (Ronda 1 de la Actividad 3.2)
-- Se ejecuta como SYSDBA: bash scripts/ops/sysdba.sh <este archivo> <evidencia>
-- Regla: la columna indexada debe quedar DESNUDA a un lado del operador. Los índices temporales de esta parte se borran al final.
WHENEVER SQLERROR EXIT FAILURE
SET LINESIZE 200 PAGESIZE 100 FEEDBACK OFF VERIFY OFF TAB OFF
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
  quitar('DROP INDEX tiendasur.ix_ped_cp');
  quitar('DROP INDEX tiendasur.ix_cli_apellidos');
  quitar('DROP INDEX tiendasur.ix_cli_telefono');
END;
/
COLUMN tel NEW_VALUE tel NOPRINT
SELECT telefono AS tel FROM tiendasur.cliente WHERE id_cliente = 4711;
CREATE INDEX tiendasur.ix_ped_cp ON tiendasur.pedido (codigo_postal);
CREATE INDEX tiendasur.ix_cli_apellidos ON tiendasur.cliente (apellidos);
PROMPT
PROMPT ===== Regla 1 · FUNCIÓN sobre la columna (Q1, inicio de sesión: 800 por segundo) =====
EXEC lab_tools.medir.consulta('Q1 rota', q'[SELECT id_cliente, nombre FROM tiendasur.cliente WHERE UPPER(email) = UPPER('Cliente4711@TiendaSur.es')]')
EXEC lab_tools.medir.consulta('Q1 reescrita', q'[SELECT id_cliente, nombre FROM tiendasur.cliente WHERE email = LOWER('Cliente4711@TiendaSur.es')]')
PROMPT (La función se aplica al DATO que llega, no a la columna: el email ya se guarda en minúsculas. Cero índices nuevos)
PROMPT
PROMPT ===== Regla 2 · ARITMÉTICA sobre la columna (Q2, pedidos del último mes) =====
EXEC lab_tools.medir.consulta('Q2 rota', q'[SELECT id_pedido, importe FROM tiendasur.pedido WHERE fecha_pedido + INTERVAL '30' DAY >= CURRENT_DATE]')
EXEC lab_tools.medir.consulta('Q2 reescrita', q'[SELECT id_pedido, importe FROM tiendasur.pedido WHERE fecha_pedido >= CURRENT_DATE - INTERVAL '30' DAY]')
PROMPT (Se despeja la columna como en una ecuación: el +30 pasa al otro lado como -30)
PROMPT
PROMPT ===== Regla 3 · CONVERSIÓN IMPLÍCITA de tipos (Q3, envíos por código postal: VARCHAR2 comparado con un número) =====
EXEC lab_tools.medir.consulta('Q3 rota', q'[SELECT id_pedido, estado FROM tiendasur.pedido WHERE codigo_postal = 30001]')
EXEC lab_tools.medir.consulta('Q3 reescrita', q'[SELECT id_pedido, estado FROM tiendasur.pedido WHERE codigo_postal = '30001']')
PROMPT -- La prueba del delito está en los predicados del plan: Oracle añadió TO_NUMBER() sobre la COLUMNA
SET SERVEROUTPUT OFF
SELECT /*+ GATHER_PLAN_STATISTICS */ COUNT(estado) FROM tiendasur.pedido WHERE codigo_postal = 30001;
SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(FORMAT => 'BASIC +PREDICATE')) WHERE plan_table_output LIKE '%filter%' OR plan_table_output LIKE '%access%';
SET SERVEROUTPUT ON FORMAT WRAPPED
PROMPT (Oracle convierte siempre la cadena en número, nunca al revés: el índice de una columna de texto queda inutilizado)
PROMPT
PROMPT ===== Regla 4 · COMODÍN a la izquierda (Q4, buscador de atención al cliente) =====
EXEC lab_tools.medir.consulta('Q4a LIKE %ez', q'[SELECT * FROM tiendasur.cliente WHERE apellidos LIKE '%ez']')
EXEC lab_tools.medir.consulta('Q4b LIKE Gonz%', q'[SELECT * FROM tiendasur.cliente WHERE apellidos LIKE 'Gonz%']')
PROMPT (Un B-tree está ordenado por el PRINCIPIO de la cadena: 'Gonz%' es un rango; '%ez' no tiene por dónde empezar.
PROMPT  Para '%ez' se necesita otra estructura: Oracle Text o, si es frecuente, una columna con la cadena al revés e índice sobre ella)
PROMPT
PROMPT ===== Regla 5 · OR con una columna SIN índice (Q5, identificar a quien llama: email o teléfono) =====
EXEC lab_tools.medir.consulta('Q5 OR sin índice en tel.', q'[SELECT * FROM tiendasur.cliente WHERE email = '&tel' OR telefono = '&tel']')
CREATE INDEX tiendasur.ix_cli_telefono ON tiendasur.cliente (telefono);
EXEC lab_tools.medir.consulta('Q5 OR con los dos índices', q'[SELECT * FROM tiendasur.cliente WHERE email = '&tel' OR telefono = '&tel']')
EXEC lab_tools.medir.consulta('Q5 como UNION', q'[SELECT * FROM tiendasur.cliente WHERE email = '&tel' UNION SELECT * FROM tiendasur.cliente WHERE telefono = '&tel']')
PROMPT (Un OR solo puede ir por índices si CADA rama tiene el suyo: basta una rama sin índice para leer la tabla entera)
PROMPT
PROMPT ===== Bonus · Q11: reescribir bien no obliga a usar el índice =====
EXEC lab_tools.medir.consulta('Q11 rota (EXTRACT)', q'[SELECT SUM(importe) FROM tiendasur.pedido WHERE EXTRACT(YEAR FROM fecha_pedido) = 2025]')
EXEC lab_tools.medir.consulta('Q11 reescrita (rango)', q'[SELECT SUM(importe) FROM tiendasur.pedido WHERE fecha_pedido >= DATE '2025-01-01' AND fecha_pedido < DATE '2026-01-01']')
PROMPT (Un año es un tercio de los pedidos: muy por encima del punto de equilibrio. El recorrido completo es lo CORRECTO aquí,
PROMPT  y la versión con rango además permite al optimizador estimar bien las filas. Sargable no significa "usa el índice")
PROMPT
PROMPT ===== Limpieza de los índices temporales de esta parte =====
DROP INDEX tiendasur.ix_ped_cp;
DROP INDEX tiendasur.ix_cli_apellidos;
DROP INDEX tiendasur.ix_cli_telefono;
SELECT COUNT(*) AS indices_tiendasur FROM dba_indexes WHERE owner = 'TIENDASUR';
EXIT
