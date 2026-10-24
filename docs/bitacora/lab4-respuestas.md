# Lab 4 - Respuestas - Julio Checa (jcheca@alu.ucam.edu)
Issue #3, branch chore/3-oracle-dba-workflow-i

## Parte A - Punto de partida, copia del Lab 3 y diagnóstico

### Punto de control: cuántos archivos salieron FUERA y por qué

Cero archivos salieron FUERA: los 26 del inventario (datafiles, tempfiles, redo, control, SPFILE y password file) están dentro del volumen `oralab-26ai-data`. Los cinco datafiles de negocio (`academia01.dbf` ... `fintech01.dbf`) aparecen con ruta `$ORACLE_HOME/dbs/...`, pero `readlink -f` los resuelve a `/opt/oracle/oradata/dbconfig/FREE/dbs/...`: en mi imagen `$ORACLE_HOME/dbs` es un enlace simbólico al volumen, así que sobreviven a `docker rm`.

Oracle los creó ahí por dos razones encadenadas: V000 escribió rutas relativas (`DATAFILE 'academia01.dbf'`) y `db_create_file_dest` está vacío (sin OMF). Sin destino por defecto y con ruta relativa, la base de partida es `$ORACLE_HOME/dbs`. Siguen siendo un defecto: viven en una carpeta que un DBA no buscaría (deberían estar en `FREE/FREEPDB1/`) y dependen de un enlace que una actualización de imagen puede cambiar.

Nota: en mi entorno `log_mode=ARCHIVELOG` (el guion mostraba NOARCHIVELOG). No afecta a este laboratorio; se aprovecha en el Lab 5.

### Reto - Informe de diagnóstico (primer informe de auditoría)

1. **Contraseñas literales de los cinco `admin_*` en V000** - riesgo ALTO: credenciales en el historial de Git para siempre. Invalidar primero con V003 (cuentas de solo esquema) y quitar la contraseña de SYS del 08.
2. **`08-aplicar-migraciones.sh` del Lab 3 pasaba `sys/<contraseña>` en la línea de comandos** - riesgo ALTO: visible con `ps` y registrado en los eventos del demonio. Se corrige con el 08 v2 (autenticación del SO).
3. **Los cinco datafiles de negocio en `$ORACLE_HOME/dbs` (dbconfig) en vez de `FREE/FREEPDB1`** - riesgo MEDIO: no se pierden con `docker rm` en mi imagen, pero están en una carpeta inesperada y atadas a un enlace simbólico. Se corrige con OFFLINE + RENAME antes de la prueba de persistencia.
4. **Sin OMF (`db_create_file_dest` vacío)** - riesgo MEDIO: cualquier `CREATE TABLESPACE` futuro con ruta relativa repite el defecto 3. Se corrige en la Parte C.
5. **Puerto 8181 publicado sin servicio detrás** - riesgo BAJO: superficie de ataque inútil, ORDS escucha en 8080 en Linux. Se corrige con el `05-crear-contenedor.sh` v2.

Orden de corrección: primero lo irreversible sobre seguridad (2 y 1: las credenciales ya están comprometidas y cada ejecución del 08 la expone de nuevo), después lo que afecta a la integridad y localización de los datos (3, que además debe hacerse antes de la prueba de fuego de la Parte C) y por último lo cosmético-red (5). El orden también respeta la dependencia: no destruyes el contenedor (C.3) antes de tener los datafiles dentro del volumen (C.1).

### Pregunta tipo examen P1

**Respuestas: A y D.**

- A correcta: `SHUTDOWN IMMEDIATE` hace checkpoint y cierra limpio; todos los archivos quedan con el mismo SCN, así que la copia no necesita recuperación con redo.
- B incorrecta: una copia en frío no exige ARCHIVELOG; ARCHIVELOG hace falta para copiar con la base abierta o recuperar hasta un punto posterior.
- C incorrecta: `IMMEDIATE` deshace las transacciones en curso (rollback) antes de cerrar; las transacciones "perdidas" nunca se confirmaron, la copia es consistente.
- D correcta: restaurada, `STARTUP` la monta y abre sin pasos extra.
- E incorrecta: RMAN es una herramienta, no un requisito; los archivos se pueden copiar con el SO.

## Parte B - La cuenta de observabilidad C##OPS_RO

### Reto - Mínimo privilegio, de verdad

Dos riesgos concretos de darle el rol DBA "para que no le falte nada":

1. **Pierde la garantía de solo lectura.** El rol DBA trae escritura y administración (`DROP`, `ALTER SYSTEM`, `ALTER TABLESPACE`, `TRUNCATE`): un despiste en la ventana equivocada de la herramienta de monitorización deja de ser un "no puedo" imposible y se convierte en una incidencia de producción. La separación de tareas (quien mira no toca) desaparece.
2. **Superficie de ataque enorme si la cuenta se filtra.** DBA incluye crear usuarios y conceder privilegios (`CREATE USER`, `GRANT`): con la contraseña de una cuenta de monitorización, un atacante obtendría control de la base completa en todos los contenedores, no lectura. Y auditoría: una cuenta de observación con DBA no es defendible ante un revisor, porque ya no demuestra mínimo privilegio.

Privilege exacto para leer el alert log (Parte J, `11-ampliar-ops-ro.sql`): `GRANT SELECT ON sys.v_$diag_alert_ext TO c##ops_ro CONTAINER = ALL;`. Conviene saber que `SELECT_CATALOG_ROLE` **no** incluye esa vista: se concede el objeto concreto y nada más (least privilege de verdad).
