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

## Parte C - Reubicar los datafiles y prueba de persistencia

### Qué cambió y qué demostré

Los cinco datafiles de negocio pasaron de `$ORACLE_HOME/dbs` (dbconfig) a `/opt/oracle/oradata/FREE/FREEPDB1/`, con `AUTOEXTEND ON NEXT 50M MAXSIZE 1G`, usando el método OFFLINE (`ALTER TABLESPACE ... OFFLINE NORMAL` → `cp -p` → `RENAME DATAFILE` → `ONLINE` → borrar el original). Intenté primero el método online y no procede: `ALTER DATABASE MOVE DATAFILE` es una opción de Enterprise Edition y Free devuelve ORA-00439, así que OFFLINE es el único camino aquí.

Prueba de fuego: con los datafiles ya dentro del volumen, hice `SHUTDOWN IMMEDIATE` → `docker rm oralab-26ai` → `05-crear-contenedor.sh` v2 (sin 8181 y sin contraseñas al reutilizar el volumen). Antes y después: mismos 5 tablespaces ONLINE, mismas 14 tablas de los cinco `admin_*` y mismo conteo. Solo cambió el identificador del contenedor: los archivos viven en el volumen.

Revisé el defecto 5 del documento del Lab 3 (K.2): en mi repo ya estaba bien (`V001__create_esquemas_negocio.sql`) y la variable es `APP_USER_PWD` (no `APP_USER_PASSWORD`, que es solo el nombre que espera la imagen): no había nada que corregir.

### Pregunta tipo examen P2

**Respuesta: B.**

`ALTER TABLESPACE tbs OFFLINE;` (checkpoint y cierre limpio del tablespace) → copia del archivo con el SO → `ALTER TABLESPACE tbs RENAME DATAFILE 'origen' TO 'destino';` (solo actualiza la ruta del control file, no mueve nada) → `ALTER TABLESPACE tbs ONLINE;` (Oracle abre y valida la cabecera del archivo nuevo).

- A incorrecta: `MOVE DATAFILE` online requiere Enterprise Edition; la base es Standard y además habría estado indisponible igualmente.
- C incorrecta: `RENAME DATAFILE` no copia nada y el tablespace debe estar OFFLINE.
- D incorrecta: `SHUTDOWN ABORT` no hace checkpoint y obligaría a recuperación de instancia; además el tablespace se puede manejar con la base abierta.

### Reto - Que no vuelva a pasar (OMF, commit propio)

**Medida aplicada:** fijar el destino por defecto de archivos en la PDB de trabajo:

```sql
ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER SYSTEM SET db_create_file_dest = '/opt/oracle/oradata/FREE/FREEPDB1' SCOPE = BOTH;
```

**Por qué ese SCOPE:** `BOTH` porque es un cambio de configuración con valor definitivo, no una prueba: quiero que ya esté activo y que siga tras el próximo arranque (si solo usara `MEMORY`, desaparecería al reiniciar; con solo `SPFILE`, no serviría hasta el siguiente arranque y ya hay que estar protegido).

**Qué cambia en el próximo `CREATE TABLESPACE tbs_x` sin cláusula DATAFILE:** sin OMF fallaría con ORA-02236 (missing path name) y quien tuviera prisa escribiría una ruta relativa, repitiendo el defecto 1. Con OMF, Oracle elige nombre y ubicación él solo dentro de `db_create_file_dest`. Lo demostré con `CREATE TABLESPACE tbs_prueba_omf;` (sin DATAFILE): creó `/opt/oracle/oradata/FREE/FREEPDB1/FREE/55E54F.../datafile/o1_mf_tbs_prue_ofs4v0tc_.dbf`, 100 MB autoextensible, y lo borró junto con el tablespace con `DROP TABLESPACE ... INCLUDING CONTENTS AND DATAFILES`.

Detalle del entorno: OMF está activo solo en FREEPDB1, que es donde vive el negocio (los datafiles de la raíz ya estaban en su carpeta estándar). Evidencia: `03b-activar-omf.script.log`.

## Parte D - Migraciones V003 (contraseñas) y V002 (datos de demostración)

### Qué corregí y cómo lo verifiqué

**V003 (defecto 2):** borrar las contraseñas de V000 no sirve, siguen en el historial de Git. Los cinco propietarios de esquema (`ADMIN_ACADEMIA`, `ADMIN_CLINICA`, `ADMIN_FINTECH`, `ADMIN_LOGISTICA`, `ADMIN_RETAIL`) pasaron a cuentas de solo esquema con `ALTER USER ... NO AUTHENTICATION`: poseen los objetos, pero nadie puede iniciar sesión con ellos, ni siquiera con la contraseña antigua. Verificado con `dba_users`: los cinco con `AUTHENTICATION_TYPE = NONE` y `ACCOUNT_STATUS = OPEN` (siguen "OPEN" porque no están bloqueadas: no tienen contraseña que bloquear).

La prueba definitiva: conecté con la contraseña literal que quedó en V000 y recibí `ORA-01017: invalid credential or not authorized; logon denied`. La credencial expuesta ya no abre nada.

**08 v2 (defecto 3):** el script de migraciones ya no construye `sys/$ORACLE_PWD@...` (visible con `ps` y registrado en los eventos del demonio de Docker): aplica cada migración con `sqlplus -s -L / as sysdba` dentro del contenedor, es decir, autenticación del sistema operativo. No hay contraseña que filtrar.

**V002:** cargó 20 000 estudiantes, 40 asignaturas y 60 000 matrículas en Academia, deterministas (fila 101 = `00000101X`, `ACTIVO`) y con `DBMS_STATS.GATHER_SCHEMA_STATS` para que el optimizador no invente estimaciones. La repetición confirmó la idempotencia: «V002 ya aplicada (20000 estudiantes): no se inserta nada» y las cifras no se duplicaron. Son los datos con los que trabajarán las Partes G, K, L y M.

### Pregunta tipo examen P-D1

**Respuesta: C.** `ALTER USER app_owner NO AUTHENTICATION;` convierte la cuenta en de solo esquema (schema-only account): ni siquiera quien conoce la contraseña antigua puede entrar, porque la cuenta no tiene ninguna forma de autenticarse.

- A incorrecta: `ACCOUNT LOCK` bloquea, pero la contraseña sigue existiendo; con `ACCOUNT UNLOCK` vuelve a servir.
- B incorrecta: `PASSWORD EXPIRE` obliga a cambiarla en el próximo inicio; alguien puede iniciar sesión con la nueva.
- D incorrecta: quitar `CREATE SESSION` impediría el acceso, pero deja la contraseña viva y administrable; y en una PDB la comprobación del examen es la semántica de la cuenta, no un privilegio que se puede devolver.

## Parte E - Instancia y base de datos, arranque por etapas y alert log

### Instancia frente a base de datos (E.1 y E.2)

Dos entidades distintas que responden a dos preguntas distintas. `v$instance` (la INSTANCIA: memoria + procesos) me dio `FREE`, arrancada el 2026-10-24 11:12:24, es decir, del día en que recreé el contenedor en la Parte C. `v$database` (la BASE: archivos) me dio DBID `1509902213`, creada el 2026-07-05, es decir, de la fecha en que se construyó la imagen. La base lleva existiendo desde julio; la instancia, desde hace unos minutos: eso es exactamente lo que significa "los archivos viven en disco, la instancia vive mientras hay servicio".

El DBID no cambió al recrear el contenedor, pero el HOST_NAME sí (`f49e437017b9`, el ID del contenedor nuevo): el contenedor es desechable, la identidad de la base no.

Desde Linux se ve la misma instancia por otro lado: 57 procesos de background `db_*_FREE` (PMON, DBW0, LGWR, VKTM...), el listener `tnslsnr` aparte de la instancia, y en disco los archivos del CDB y de FREEPDB1 con los cinco datafiles de negocio ya en su carpeta estándar. Detalle: el listener registra cuatro servicios (`FREE`, `FREEXDB`, `freepdb1` y el GUID `55e54f...` que usa OMF).

### Punto de control: los dos errores esperados del arranque por etapas

- **ORA-01507 (`database not mounted`) en NOMOUNT:** `v$database` es una vista que lee el control file, y en NOMOUNT el control file todavía no está abierto. En cambio `v$parameter` sí responde porque sus valores ya están en la memoria de la instancia (los leyó del SPFILE al arrancar). Por eso la etapa existe: sin control file no hay nada que "montar".
- **ORA-01219 en MOUNT:** `dba_tables` es una vista del diccionario, y el diccionario vive en las tablas de SYSTEM, que están en un datafile que sigue cerrado. En MOUNT solo funcionan las vistas fijas (V$/X$), que leen memoria y control file.

Y FREEPDB1 se abrió sola tras `ALTER DATABASE OPEN`: no es magia, es el estado guardado (`dba_pdb_saved_states` lo confirma con STATE = OPEN), que es exactamente lo que comprobamos en la Parte C al recrear el contenedor.

### Reto - El parte del reinicio (a partir del alert log)

- **¿A qué hora se pidió la parada?** 2026-10-24T11:21:03.446Z, con `SHUTDOWN IMMEDIATE` desde `sqlplus@f49e437017b9` (mi sesión de la Parte E.3). El mensaje "further logons disabled" confirma el cierre ordenado.
- **¿Cuánto tardó en abrir la base?** El arranque empezó a las 11:21:08.358Z y `ALTER DATABASE OPEN` se completó a las 11:21:12.459Z: unos 4 segundos desde que nace la instancia hasta OPEN; unos 9 segundos de downtime total contando la parada (11:21:03 → 11:21:12).
- **¿Hubo recuperación de instancia?** No en el sentido fuerte: el cierre fue limpio (`SHUTDOWN IMMEDIATE` hace checkpoint). El mensaje "Crash Recovery excluding pdb 2/3 which was cleanly closed" es el paso normal de recuperación de hilo que Oracle ejecuta siempre al abrir, con redo de sobra disponible (y además estamos en ARCHIVELOG): no hubo transacciones que recuperar.
- **Errores, clasificados:**
  - `ORA-00800 [Set Priority Failed] [VKTM] / [LGWR]` → **conocido, se excluye de alertas**: el contenedor no tiene la capacidad `CAP_SYS_NICE` para subir la prioridad de esos procesos. Es un aviso "soft", la base funciona con normalidad.
  - `ORA-27302 / ORA-27303 (spstp:9, chdir() = 2)` → **a investigar, pero localizado**: solo apareció en el primer arranque dentro del contenedor recreado (OS id 39), un `chdir` a un directorio inexistente (error 2 = ENOENT) durante el arranque de procesos servidor. No se ha repetido en ningún arranque posterior y la base abre y sirve correctamente; lo dejo documentado y vigilado, que es lo que haría con un aviso raro de una imagen de contenedor.

### Preguntas tipo examen P3, P4 y P5

**P3: respuestas A y C.**
- A correcta: `STARTUP_TIME` es de la instancia; cada `STARTUP` la cambia (mi evidencia lo muestra: 11:12:24 tras recrear el contenedor).
- B incorrecta: el DBID identifica a la BASE y sobrevive a recrear el contenedor (lo comprobé: mismo `1509902213` antes y después de la Parte C).
- C correcta: `CREATED` es de la base (2026-07-05, fecha de construcción de la imagen), no de su arranque.
- D incorrecta: una instancia monta UNA base; dos instancias del mismo clúster RAC comparten una base, no al revés.
- E incorrecta: `v$database` se puede consultar en MOUNT (lo vi en la etapa 3: devuelve `FREE MOUNTED NOARCHIVELOG/ARCHIVELOG`).

**P4: respuestas A y C.**
- A correcta: en NOMOUNT los parámetros ya están en memoria (SPFILE leído), `v$parameter` responde.
- C correcta: recrear el control file es justo el uso clásico de NOMOUNT: `CREATE CONTROLFILE` necesita la instancia sin los control files originales montados.
- B y E incorrectas: `dba_users`/diccionario requieren OPEN (datafiles de SYSTEM abiertos).
- D incorrecta: `ALTER DATABASE ARCHIVELOG` exige MOUNT (el control file debe estar abierto y la base desmontable).

**P5: respuesta B (MOUNT).** El commando reescribe la cabecera de los control files y el modo de registro, así que necesita los control files abiertos (MOUNT) y la base no debe estar OPEN.

## Parte F - Parámetros: SPFILE, SCOPE y PDB

### Lo que leí (F.1)

La instancia arrancó con SPFILE (`/opt/oracle/product/26ai/dbhomeFree/dbs/spfileFREE.ora`, que en mi imagen es enlace al volumen). El SPFILE solo especifica **18** parámetros, pero `v$parameter` documenta **564**: el resto toman valor por defecto o derivado. De los 564, 18 no están en su valor por defecto y 134 son estáticos (`ISSYS_MODIFIABLE = FALSE`).

Los que marcan la arquitectura del curso: `db_block_size = 8192` (la página de 8 KB de la Unidad 3, fijado al crear la base y que ya nunca podrá cambiar), `sga_target = 1536M`, `pga_aggregate_target = 512M`, `pga_aggregate_limit = 2G`, `processes = 200`, `compatible = 23.6.0` (solo puede subirse). Detalle interesante en mi entorno: `db_create_file_dest` sale vacío en CDB$ROOT porque el OMF de la Parte C lo fijé **en FREEPDB1** (es un parámetro modificable por PDB).

### Lo que cambié y deshice (F.2)

Recorrí los cinco alcances y el script devuelve la instancia exactamente como estaba:

- `open_cursors` con `SCOPE=MEMORY`: 400 en memoria, 300 en SPFILE (se pierde al reiniciar).
- `open_cursors` con `SCOPE=BOTH` + comentario: 500 en ambos, y el comentario queda visible en `update_comment`. Deshecho al valor original 300.
- `db_files` (estático): `SCOPE=MEMORY` → **ORA-02095**; `SCOPE=SPFILE` → aceptado pero PENDIENTE hasta el próximo arranque (en memoria sigue 200, en el SPFILE 300). Deshecho con `ALTER SYSTEM RESET db_files SCOPE=SPFILE`, que borra la línea y vuelve al valor por defecto.
- `processes` → **ORA-02097 + ORA-02095**: aunque `v$parameter` dice `ISSYS_MODIFIABLE = IMMEDIATE`, en la práctica es estático (dimensiona estructuras de la SGA al arrancar). `memory_size` → **ORA-62352**: solo es dinámico si la instancia arrancó con él.
- Nivel PDB: dentro de FREEPDB1 fijé `open_cursors = 350` (solo esa PDB) y `processes` devolvió **ORA-65040** (parámetro de instancia, no se toca desde una PDB). Tras `RESET`, FREEPDB1 volvió a heredar el 300 del CDB.
- Nivel sesión: `ALTER SESSION SET nls_date_format`, solo para esta conexión.
- Seguro antes de tocar el SPFILE: `CREATE PFILE FROM SPFILE` (32 líneas) y `CREATE PFILE FROM MEMORY` (122 líneas). La diferencia es la respuesta a "por qué el SPFILE solo tiene 18 líneas".

### Reto - Petición de cambio (open_cursors a 1000)

- **Valor actual y de dónde sale:** `open_cursors = 300`, fijado explícitamente en el SPFILE (no es por defecto: `ISDEFAULT = FALSE`), modificable por sesión y por PDB.
- **Valor propuesto:** 1000.
- **Alcance:** `ALTER SYSTEM SET open_cursors = 1000 SCOPE = BOTH;` — es un parámetro dinámico (`ISSYS_MODIFIABLE = IMMEDIATE`), así que BOTH le aplica ya y lo deja escrito para el próximo arranque. `MEMORY` no valdría (desaparecería al reiniciar y el incidente volvería); `SPFILE` no valdría (la aplicación sufriría hasta el siguiente reinicio).
- **Cómo lo pruebo:** (1) compruebo memoria y SPFILE (`v$parameter` y `v$spparameter`); (2) mido antes y después el uso real con `SELECT MAX(a.value) FROM v$sesstat a, v$statname b WHERE a.statistic# = b.statistic# AND b.name = 'opened cursors current';` y reviso `v$open_cursor` por aplicación; (3) confirmo que desaparecen los ORA-01000 del log de la aplicación durante un pico de carga.
- **Rollback:** `ALTER SYSTEM SET open_cursors = 300 SCOPE = BOTH;` (instantáneo, sin reinicio).
- **Evidencia que guardo:** spool del cambio, y el PFILE versionado en `evidencia/config/` que servirá para detectar deriva de configuración con `git diff`.
- **Advertencia profesional:** ORA-01000 casi siempre delata cursores que la aplicación no cierra; subir el límite solo retrasa el problema y consume más memoria por sesión. Lo correcto es entregar el número con medición y abrir un ticket para el equipo de desarrollo con `v$open_cursor` como prueba.

### Preguntas tipo examen P6, P7 y P8

**P6: respuesta B.** Sin cláusula SCOPE, el valor por defecto es BOTH cuando la instancia arrancó con SPFILE (MEMORY si arrancó con PFILE). Por eso el cambio se aplica en memoria y queda escrito en el SPFILE.

**P7: respuesta C.** `processes` no es modificable a nivel de PDB (`ISPDB_MODIFIABLE = FALSE`): desde FREEPDB1 Oracle responde **ORA-65040: Operation is not allowed from within a pluggable database**. No es por ser estático (eso daría ORA-02095): el problema es el nivel.

**P8: respuestas A y C.** Con un SPFILE con un valor imposible la instancia no pasa de NOMOUNT: se arranca con el PFILE bueno (`STARTUP PFILE='/ruta/init_bueno.ora'`) y desde ahí se repara el SPFILE con `CREATE SPFILE FROM PFILE='/ruta/init_bueno.ora'`. RESET en MEMORY no aplica (MEMORY no escribe en el SPFILE), RESETLOGS es de recuperación y SHUTDOWN ABORT no arregla nada.
