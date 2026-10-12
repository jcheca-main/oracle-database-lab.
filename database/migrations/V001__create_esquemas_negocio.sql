-- database/migrations/V001__create_esquemas_negocio.sql
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER = FREEPDB1;
-- ===== Academia: integridad referencial =====
ALTER SESSION SET CURRENT_SCHEMA = admin_academia;
CREATE TABLE aca_estudiantes (
 estudiante_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 dni VARCHAR2(20) CONSTRAINT uq_aca_dni UNIQUE NOT NULL,
 nombres VARCHAR2(100) NOT NULL,
 apellidos VARCHAR2(100) NOT NULL,
 email_institucional VARCHAR2(150) CONSTRAINT uq_aca_email UNIQUE NOT NULL,
 estado VARCHAR2(20) DEFAULT 'ACTIVO' CONSTRAINT chk_aca_estado
 CHECK (estado IN ('ACTIVO','INACTIVO','EGRESADO','SUSPENDIDO')),
 fecha_registro TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL);
CREATE TABLE aca_asignaturas (
 asignatura_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 codigo VARCHAR2(20) CONSTRAINT uq_aca_codigo UNIQUE NOT NULL,
 nombre VARCHAR2(150) NOT NULL,
 creditos NUMBER(2) CONSTRAINT chk_aca_creditos CHECK (creditos > 0 AND creditos <= 10));
CREATE TABLE aca_matriculas (
 matricula_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 estudiante_id NUMBER NOT NULL CONSTRAINT fk_aca_mat_est REFERENCES aca_estudiantes(estudiante_id),
 asignatura_id NUMBER NOT NULL CONSTRAINT fk_aca_mat_asi REFERENCES aca_asignaturas(asignatura_id),
 periodo VARCHAR2(10) NOT NULL,
 fecha_matricula TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
 CONSTRAINT uq_aca_matricula_unica UNIQUE (estudiante_id, asignatura_id, periodo));
CREATE INDEX idx_aca_mat_est ON aca_matriculas(estudiante_id);
CREATE INDEX idx_aca_mat_asi ON aca_matriculas(asignatura_id);
-- ===== Clinica: datos sensibles (PII) =====
ALTER SESSION SET CURRENT_SCHEMA = admin_clinica;
CREATE TABLE cli_pacientes (
 paciente_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 numero_seguro VARCHAR2(50) CONSTRAINT uq_cli_seguro UNIQUE NOT NULL,
 nombre_completo VARCHAR2(200) NOT NULL,
 fecha_nacimiento DATE NOT NULL,
 telefono_contacto VARCHAR2(20),
 datos_sensibles_enmascarar VARCHAR2(4000));
CREATE TABLE cli_medicos (
 medico_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 licencia_medica VARCHAR2(50) CONSTRAINT uq_cli_licencia UNIQUE NOT NULL,
 especialidad VARCHAR2(100) NOT NULL,
 estado_operativo VARCHAR2(20) DEFAULT 'DISPONIBLE' CONSTRAINT chk_cli_estado
 CHECK (estado_operativo IN ('DISPONIBLE','CIRUGIA','VACACIONES','INACTIVO')));
CREATE TABLE cli_citas (
 cita_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 paciente_id NUMBER NOT NULL CONSTRAINT fk_cli_cita_pac REFERENCES cli_pacientes(paciente_id),
 medico_id NUMBER NOT NULL CONSTRAINT fk_cli_cita_med REFERENCES cli_medicos(medico_id),
 fecha_hora_cita TIMESTAMP NOT NULL,
 motivo VARCHAR2(500),
 estado VARCHAR2(20) DEFAULT 'PROGRAMADA' CONSTRAINT chk_cli_estado_cita
 CHECK (estado IN ('PROGRAMADA','COMPLETADA','CANCELADA','NO_ASISTE')),
 creado_el TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 CONSTRAINT uq_cli_horario_medico UNIQUE (medico_id, fecha_hora_cita));
CREATE INDEX idx_cli_citas_paciente ON cli_citas(paciente_id);
CREATE INDEX idx_cli_citas_fecha ON cli_citas(fecha_hora_cita);
-- ===== Retail: alto volumen OLTP =====
ALTER SESSION SET CURRENT_SCHEMA = admin_retail;
CREATE TABLE ret_productos (
 producto_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 sku VARCHAR2(50) CONSTRAINT uq_ret_sku UNIQUE NOT NULL,
 nombre VARCHAR2(200) NOT NULL,
 precio_base NUMBER(10,2) CONSTRAINT chk_ret_precio CHECK (precio_base >= 0) NOT NULL,
 stock_actual NUMBER(8) DEFAULT 0 CONSTRAINT chk_ret_stock CHECK (stock_actual >= 0) NOT NULL);
CREATE TABLE ret_ventas_cabecera (
 venta_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 fecha_transaccion TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
 caja_id NUMBER NOT NULL,
 metodo_pago VARCHAR2(20) CONSTRAINT chk_ret_pago
 CHECK (metodo_pago IN ('EFECTIVO','TARJETA','QR','TRANSFERENCIA')),
 total_venta NUMBER(12,2) DEFAULT 0 NOT NULL);
CREATE TABLE ret_ventas_detalle (
 detalle_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 venta_id NUMBER NOT NULL CONSTRAINT fk_ret_det_ven REFERENCES ret_ventas_cabecera(venta_id) ON DELETE CASCADE,
 producto_id NUMBER NOT NULL CONSTRAINT fk_ret_det_prod REFERENCES ret_productos(producto_id),
 cantidad NUMBER(6) CONSTRAINT chk_ret_cantidad CHECK (cantidad > 0) NOT NULL,
 precio_unitario NUMBER(10,2) NOT NULL,
 subtotal NUMBER(12,2) GENERATED ALWAYS AS (cantidad * precio_unitario) VIRTUAL);
CREATE INDEX idx_ret_ventas_fecha ON ret_ventas_cabecera(fecha_transaccion);
CREATE INDEX idx_ret_detalle_venta ON ret_ventas_detalle(venta_id);
CREATE INDEX idx_ret_detalle_prod ON ret_ventas_detalle(producto_id);
-- ===== Logistica: trazabilidad y estados concurrentes =====
ALTER SESSION SET CURRENT_SCHEMA = admin_logistica;
CREATE TABLE log_almacenes (
 almacen_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 codigo_iata VARCHAR2(3) CONSTRAINT uq_log_iata UNIQUE NOT NULL,
 ciudad VARCHAR2(100) NOT NULL,
 capacidad_maxima NUMBER NOT NULL);
CREATE TABLE log_envios (
 envio_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tracking_number VARCHAR2(100) CONSTRAINT uq_log_tracking UNIQUE NOT NULL,
 almacen_origen NUMBER NOT NULL CONSTRAINT fk_log_env_ori REFERENCES log_almacenes(almacen_id),
 almacen_destino NUMBER NOT NULL CONSTRAINT fk_log_env_des REFERENCES log_almacenes(almacen_id),
 peso_kg NUMBER(6,2) NOT NULL,
 estado_actual VARCHAR2(30) DEFAULT 'EN_PREPARACION' CONSTRAINT chk_log_estado
 CHECK (estado_actual IN ('EN_PREPARACION','EN_TRANSITO','EN_ADUANA','ENTREGADO','EXTRAVIADO')),
 ultima_actualizacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL);
CREATE TABLE log_eventos_tracking (
 evento_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 envio_id NUMBER NOT NULL CONSTRAINT fk_log_evt_env REFERENCES log_envios(envio_id),
 estado_registrado VARCHAR2(30) NOT NULL,
 fecha_evento TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
 observaciones VARCHAR2(500));
CREATE INDEX idx_log_eventos_envio ON log_eventos_tracking(envio_id);
-- ===== Fintech: ACID y precision numerica =====
ALTER SESSION SET CURRENT_SCHEMA = admin_fintech;
CREATE TABLE fin_cuentas (
 cuenta_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 numero_cuenta VARCHAR2(20) CONSTRAINT uq_fin_numero UNIQUE NOT NULL,
 tipo_moneda VARCHAR2(3) DEFAULT 'USD' NOT NULL,
 saldo NUMBER(18,4) DEFAULT 0 NOT NULL,
 estado VARCHAR2(15) DEFAULT 'ACTIVA' CONSTRAINT chk_fin_estado
 CHECK (estado IN ('ACTIVA','CONGELADA','CERRADA')),
 CONSTRAINT chk_fin_saldo_positivo CHECK (saldo >= 0) INITIALLY DEFERRED DEFERRABLE);
CREATE TABLE fin_transacciones (
 tx_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 cuenta_origen NUMBER CONSTRAINT fk_fin_tx_ori REFERENCES fin_cuentas(cuenta_id),
 cuenta_destino NUMBER CONSTRAINT fk_fin_tx_des REFERENCES fin_cuentas(cuenta_id),
 monto NUMBER(18,4) CONSTRAINT chk_fin_monto CHECK (monto > 0) NOT NULL,
 tipo_operacion VARCHAR2(20) CONSTRAINT chk_fin_operacion
 CHECK (tipo_operacion IN ('DEPOSITO','RETIRO','TRANSFERENCIA','COMISION')),
 fecha_tx TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
 hash_auditoria VARCHAR2(256));
CREATE INDEX idx_fin_tx_origen ON fin_transacciones(cuenta_origen);
CREATE INDEX idx_fin_tx_destino ON fin_transacciones(cuenta_destino);
CREATE INDEX idx_fin_tx_fecha ON fin_transacciones(fecha_tx);
PROMPT == Verificacion: tablas por esquema ==
SELECT owner, COUNT(*) AS tablas FROM dba_tables
WHERE owner LIKE 'ADMIN\_%' ESCAPE '\' GROUP BY owner ORDER BY owner;
EXIT
