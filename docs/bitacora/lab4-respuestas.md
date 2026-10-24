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

## Parte G - Memoria: SGA, Buffer Cache, análisis de sentencias y PGA

### Modelo de memoria medido (G.1)

`memory_size = 0` y `memory_target = 0` con `sga_target = 1536M`: esta instancia usa **ASMM** (Oracle reparte la SGA entre buffer cache, shared pool, large pool y java pool), no AMM. La PGA se gestiona aparte con `pga_aggregate_target = 512M` y `pga_aggregate_limit = 2G`. En mi medición: SGA de 1529 MB (buffer cache 1072, shared pool 416) y `total PGA allocated = 409 MB` con `cache hit percentage = 100` y cero sobredimensionados.

Ojo con el asesor: `v$sga_target_advice` da el mismo factor de tiempo (1) para desde 768 MB hasta 3072 MB, porque es una base ociosa donde todo cabe en caché. Concluir "la SGA sobra" a partir de esa tabla sería un error de análisis: los asesores solo sirven con carga real.

Detalle propio de mi entorno: en el top de PGA aparecen ARC0-ARC3 (los archivadores), que en el entorno del guion no existían porque estaba en NOARCHIVELOG; mi base está en ARCHIVELOG.

### Experimento 1 - El Buffer Cache convierte lecturas físicas en lógicas (G.2)

`ACA_ESTUDIANTES` ocupa 244 bloques. Tras `FLUSH BUFFER_CACHE` (solo laboratorio):

- **Ronda 1 (caché fría):** 463 lecturas lógicas, **256 físicas**.
- **Ronda 2 (caché caliente):** 247 lecturas lógicas, **0 físicas**.
- `v$bh`: **245 bloques** de la tabla residentes en el Buffer Cache.

Interpretación:
- **¿Por qué las físicas desaparecen y las lógicas siguen?** Toda lectura física termina en lógica: el bloque se trae del disco a la caché y desde ahí se lee. La ronda 2 no repite I/O, pero el recorrido por los mismos bloques es idéntico: el coste de la ronda 2 es memoria pura.
- **¿Por qué más lecturas físicas que bloques de tabla (256 vs 244)?** El full scan no lee solo las filas: lee la cabecera del segmento y el mapa de extensiones, y en la primera ronda además se arrastraron bloques auxiliares (diccionario/undo) que provocaron que las lecturas lógicas de la ronda 1 (463) fueran mayores que las de la ronda 2 (247). El invariante es la ronda 2: 247 lecturas lógicas ≈ 244 bloques de la tabla + cabecera, que es el coste real de barrer la tabla.
- **Tasa de acierto de la ronda 2:** 1 − 0/247 = **100 %**.

### Experimento 2 - Análisis duro frente a variables de enlace (G.3)

1000 consultas sobre la misma tabla:

| Medida | Literales | Bind (:id) |
|---|---|---|
| Análisis totales | 1054 | 1 |
| Análisis duros | 1011 | 1 |
| CPU de análisis | 530 ms | ~0 ms |
| Tiempo total | 530 ms | 10 ms |
| Cursores en V$SQL | 489 (de 1000) | 1 |
| Memoria en Shared Pool | 17 612 KB | 39 KB |

Con literales, el 100 % del tiempo fue analizar, no ejecutar (53 veces más lento). Y los 489 cursores que sobreviven en `V$SQL` ocupan 17 MB: los otros 511 ya fueron expulsados (aged out), que también es coste porque habrá que reanalizarlos. Con la variable de enlace, PL/SQL mantiene el cursor abierto entre iteraciones: un análisis, mil ejecuciones.

### Experimento 3 - La PGA ordena en memoria o se va a TEMP (G.3)

Ordenar las 60 000 matrículas:

- **PGA automática:** `sorts (memory) = 11`, `sorts (disk) = 0`, 30 ms; `v$sql_workarea` muestra OPTIMAL con 0 KB en TEMP (usó ~2,4 MB de los ~2,7 MB estimados).
- **Manual con 64 KB:** `sorts (disk) = 1`, **450 ms** (15× más); `LAST_EXECUTION = '6 PASSES'` y **3072 KB escritos en TEMP**.

Y el matiz que el examen pregunta: `maximum PGA allocated` (462 MB) se acerca al objetivo (512 MB) sin ningún error: el objetivo no es un límite; el límite duro es `pga_aggregate_limit` (2 GB), y al llegar a él Oracle empezaría a cortar operaciones con ORA-04036.

### Reto - Encontrar a los culpables (08-reto-literales.sql)

Consulta sobre `V$SQL` agrupando por `force_matching_signature` con más de 50 cursores. La salida: **una sola firma con 426 cursores distintos**, 426 ejecuciones y 15 165 KB de shared pool, con el ejemplo `SELECT /* lab4_literal */ COUNT(*) FROM admin_academia.aca_est...`. Es decir, la consulta del experimento, queOracle no puede unificar porque cada literal es un texto distinto. En una base real, esa tabla es la lista de sospechosos para exigir bind variables al equipo de desarrollo.

### Preguntas tipo examen P9, P10, P-G1 y P-G2

**P9: respuesta B.** Con `SGA_TARGET` fijado, ASMM gestiona el reparto, y `DB_CACHE_SIZE` actúa como suelo: el buffer cache crecerá y encogerá según la carga, pero nunca por debajo de 512 MB.
- A incorrecta: ASMM puede llevarlo muy por encima de 512 MB.
- C incorrecta: `MEMORY_TARGET = 0` significa que AMM NO está activo; con ASMM, SGA y PGA se gestionan por separado.
- D incorrecta: no se ignora; se convierte en el mínimo.

**P10: respuestas A y D.** La PGA de un proceso servidor dedicado contiene el área de trabajo (sort/hash/bitmap merge) y la memoria de estado de sesión. Shared pool, log buffer y buffer cache son de la SGA.

**P-G1: respuesta B.** La solución definitiva es corregir la aplicación para usar variables de enlace. A falla porque la Shared Pool no es la cura (solo aloja más cursores malos y expulsa buenos), C empeora el problema (todo el mundo re-analiza cada hora) y D es el parche temporal que oculta el defecto y degrada la elección de planes.

**P-G2: respuesta B.** `6 PASSES` significa que el área de trabajo no cupo en la PGA y Oracle tuvo que escribir y releer los tramos desde TEMP seis veces: con la misma tabla pequeña ya pasó de 30 ms a 450 ms; con datos reales sería cuestión de minutos.

## Parte H - Procesos de background y procesos servidor

### Los dos libros de contabilidad (H.1 y H.2)

Desde Oracle (`09-procesos.sql`): **87 procesos background y 7 servidor**, con 54 PIDs de Linux para los 87 background: hay procesos Oracle que son hilos dentro de un mismo proceso Linux (SCMN y los spawners), por eso `procesos_oracle > procesos_linux`. Los obligatorios están todos con su PID: PMON 1130, LREG 1194, SMON 1188, DBW0 1180, LGWR 1182, CKPT 1184, MMON 1204, MMNL 1206, RECO 1192, más PSP0, PMAN, MMAN, VKTM, DIAG, DIA0, CLMN, CJQ0 y ARC0.

**Arcn:** salen **4 procesos ARC0-ARC3**, no 0 como en el entorno del guion: mi base está en `ARCHIVELOG` (ya lo anoté en la Parte A). Es la diferencia exacta que el guion prevé: el archivador es opcional en NOARCHIVELOG y obligatorio en ARCHIVELOG.

**Mi sesión:** SID 61 en H.1 (218 en la segunda pasada), `C##OPS_RO` desde `PortatilAuxi`, `PROGRAM = SQLcl` y un SPID propio: arquitectura de **servidor dedicado**, un proceso de Linux por conexión. En `v$session` también se veían las sesiones de usuario del momento: mi SQLcl y las sesiones de trabajos `J000/J001/J002`.

Desde Linux (`09-procesos-so.sh <spid>`): el **SPID de LGWR (1182) es exactamente el PID de `db_lgwr_FREE`** en `/proc` dentro del contenedor. PMON 1130, DBW0 1180, CKPT 1184, SMON 1188, RECO 1192, LREG 1194, MMON 1204, MMNL 1206 también coinciden uno a uno. Recuento en `/proc`: 58-61 procesos `db_*_FREE`/`ora_*_FREE`, 0 `oracleFREE` (no había sesión SQLcl abierta en ese instante) y 1 `tnslsnr` (el listener es un proceso aparte de la instancia).

Tres matices del guion que compruebo en mi entorno:

- **No comparo con `docker top`:** ahí vería el PID del anfitrión (otro espacio de nombres de PID). El cruce correcto es leer `/proc` desde dentro del contenedor, que es lo que hace el script: por eso el SPID de `v$process` y el PID de Linux son el mismo número.
- **El RSS no se suma:** cada background muestra ~100 MB de RSS, pero casi toda esa memoria es la SGA compartida, repetida en cada proceso. Sumando 60 procesos daría >5 GB en un contenedor que usa ~2 GB. La memoria real la da `v$sga + v$pgastat` (Parte G).
- **Servidor dedicado, no shared:** 0 procesos `oracleFREE` mientras nadie estaba conectado, y uno por cada SQLcl que abro.

### Preguntas tipo examen P11 y P12

**P11: respuesta C (LGWR).** El COMMIT solo espera a LGWR (`write-ahead logging`): la red va primero al log buffer y LGWR la escribe en los redo logs online antes de devolver el control. DBWn no entra en el COMMIT: los bloques de datos llegan al datafile después, en checkpoints o cuando faltan buffers libres. CKPT actualiza cabeceras y control file, ARCn copia los redo llenos y SMON recupera la instancia.

**P12: respuestas B y D (PMON y SMON).** Son los dos obligatorios en cualquier instancia: PMON limpia procesos de usuario caídos (deshace transacciones, libera bloqueos) y SMON se ocupa de la recuperación de instancia al abrir. ARC0 solo existe en ARCHIVELOG (en mi base sí aparece, pero no es obligatorio), RECO solo hace falta con transacciones distribuidas y CJQ0 solo con trabajos programados.

### Reto - La sesión que más consume (dos terminales)

- **Terminal 1 (SYSDBA):** `docker exec -i oralab-26ai sqlplus / as sysdba`, `ALTER SESSION SET CONTAINER = FREEPDB1;` y la consulta que tarda unos segundos:
  `SELECT COUNT(*) FROM admin_academia.aca_matriculas a, admin_academia.aca_matriculas b WHERE a.matricula_id < 3000;`
  Es un producto cartesiano de **179.940.000 filas** y tarda ~5,5 s por pasada; la lancé 4 veces seguidas en segundo plano para tener margen de muestreo.
- **Terminal 2 (C##OPS_RO):** con `09-reto-sesion-larga.sql` (`v$session` + `v$process`), los tres valores del primer diagnóstico de rendimiento:
  - **SID = 46** (SERIAL# 38175)
  - **SPID = 4068** (el PID real de Linux dentro del contenedor; en `/proc` es el proceso `sqlplus@...`)
  - **PGA = 3,3 MB usada / 3,4 MB asignada** (`pga_used_mem` / `pga_alloc_mem`)
- **Limpieza:** `ALTER SYSTEM KILL SESSION '46,38175' IMMEDIATE;` devuelve **ORA-00031: session marked for kill**, que no es un fallo: la sesión queda marcada y Oracle la mata al terminar la llamada en curso (el mensaje lo confirma). Verificado después: no queda ninguna sesión SYS mía; solo la sesión `OFSD` del propio contenedor.
- **Detalle de por qué importa:** la PGA de esa sesión es minúscula (3,4 MB) porque el producto cartesiano se resuelve casi entero con lecturas del Buffer Cache (caliente desde la Parte G) y el conteo no ordena; si hubiera un `ORDER BY` grande, esa misma PGA se dispararía hacia TEMP (Parte G, experimento 3). Y con el SPID en la mano puedo correlacionar con `09-procesos-so.sh` o con `docker stats` sin adivinar de qué proceso hablo.

Evidencias: `09-procesos.script.log`, `09-procesos-so.script.log`, spools `09-procesos` y `09-reto-sesion-larga`.

## Parte I - Navegar por los contenedores: qué ve cada usuario y por qué

### El mapa (I.1)

En mi CDB: `CON_ID 1 = CDB$ROOT` (READ WRITE), `2 = PDB$SEED` (READ ONLY, siempre, 810 MB), `3 = FREEPDB1` (READ WRITE con SAVE STATE, 1442 MB, los esquemas de negocio). `CON_ID 0` no es un contenedor: es el nivel "toda la CDB" (redo, instancia, procesos). Familias: `USER_` lo mío, `ALL_` lo que puedo tocar, `DBA_` todo el contenedor actual, `CDB_` el `DBA_` de todos los contenedores con `CON_ID`, `V$/GV$` memoria y control file (GV$ = todas las instancias de un RAC).

### Experimento: tres usuarios, las mismas preguntas (I.2)

- **SYS en la raíz:** `v$datafile` = **4 (root) + 3 (seed) + 9 (FREEPDB1)** = 16 datafiles, y `v$log` sale con **CON_ID 0**.
- **SYS dentro de FREEPDB1:** la misma `v$datafile` devuelve **solo CON_ID 3 (9 filas)** y `dba_tablespaces = 10`, mientras `cdb_tablespaces` solo muestra la fila de FREEPDB1: dentro de una PDB hasta las `CDB_` se filtran.
- **`lab4_analista` (local, solo CREATE SESSION):** `USER_TABLES = 0`, y los tres errores esperados: **ORA-00942** en `DBA_TABLES`, en `V$SESSION` y en `admin_academia.aca_estudiantes` (Oracle no revela lo que no puedes ver: responde "no existe"), y **ORA-01031** al intentar `SET CONTAINER = CDB$ROOT` (ni tiene el privilegio ni la cuenta existe en la raíz).
- **`lab4_analista` + `GRANT READ ANY TABLE ON SCHEMA admin_academia` (23ai):** ve las **3 tablas** del esquema y cuenta **20 000 estudiantes**, sigue sin ver `admin_clinica` (ORA-00942) y el `UPDATE` devuelve **ORA-41900: missing UPDATE privilege** (el mensaje de 23ai dice el privilegio y el objeto exactos).
- **`c##lab4_auditor` (común sin CONTAINER_DATA) en la raíz:** `cdb_tablespaces` = **solo 5 filas (CON_ID 1)** y `v$session` = 87 filas de CON_ID 0 + 3 de CON_ID 1, ninguna de FREEPDB1. Con `SET CONTAINER = FREEPDB1` sí ve los 10 tablespaces de la PDB. `cdb_container_data` confirma la diferencia con mi cuenta: **`C##OPS_RO  Y  Y`** (DEFAULT_ATTR y ALL_CONTAINERS) y `C##LAB4_AUDITOR` no aparece.
- Limpieza: `USUARIOS_LAB4_RESTANTES = 0`.

### Punto de control - interpretar la salida

1. **¿Por qué `V$LOG` tiene CON_ID 0 y el redo no pertenece a ninguna PDB?** Porque el redo es de la **instancia**: todas las PDB de la CDB comparten el mismo redo log y el mismo control file (una instancia, un redo, varios pisos). No existe "redo de FREEPDB1", así que la fila se publica en el nivel 0 (toda la CDB) y sale igual estés donde estés. Por eso `ALTER DATABASE ARCHIVELOG` es una operación de instancia (Parte F: exige MOUNT) y no se puede configurar por PDB.
2. **¿Qué sentencia haría que `C##LAB4_AUDITOR` viera las sesiones de FREEPDB1?** Conectado como SYS en la raíz: `ALTER USER c##lab4_auditor SET CONTAINER_DATA = ALL CONTAINER = CURRENT;`. No sirve `SELECT ANY DICTIONARY` ni abrir más PDBs: el filtro no es de privilegio de catálogo sino de **atributo CONTAINER_DATA** de la cuenta (la Parte B ya me mostró `C##OPS_RO` con `ALL_CONTAINERS = Y`, por eso yo sí veo todos).
3. **¿Qué habría pasado con `SELECT ANY TABLE`?** Habría leído también `ADMIN_CLINICA` y cualquier otro esquema de la PDB: no distingue esquemas, es un privilegio de escala amplia que incumple mínimo privilegio. `READ ANY TABLE ON SCHEMA admin_clinica` abre exactamente ese esquema, incluidas las tablas que se creen después (que es lo que pedía la auditora), y nada más.

### El diccionario se describe a sí mismo (I.3)

Con la misma cuenta (`C##OPS_RO`, servicio FREE): **USER_ 656, ALL_ 590, DBA_ 1309, CDB_ 1307, V$ 921, GV$ 880** vistas. La misma pregunta con las dos familias: `DBA_TABLESPACES = 5` (solo la raíz) frente a `CDB_TABLESPACES = 15` (5 de CDB$ROOT + 10 de FREEPDB1; la semilla no cuenta porque está READ ONLY y las `CDB_` la excluyen) — y eso es posible porque `C##OPS_RO` tiene `CONTAINER_DATA = ALL`: sin ese atributo solo vería las 5. `v$fixed_table` muestra **1591 tablas X$** y **1803 vistas**. Y `V$LOG` se describe sobre `x$kccle` + `x$kccrt`: "kcc" es la capa del control file (kernel cache control file), que explica por qué `V$LOG` solo responde cuando el control file está abierto (MOUNT, Parte E).

### Ciclo de vida de una PDB y usuarios (I.4)

- **Usuarios comunes vs locales:** `SYS`, `SYSTEM`, `C##OPS_RO` = `COM YES` y aparecen en CDB$ROOT **y** FREEPDB1; `PDBADMIN`, `ADMIN_ACADEMIA` = `NO`, solo en FREEPDB1.
- **Errores de examen, todos disparados en mi entorno:** `common_user_prefix = C##` (aquí sí está fijado; el guion mostraba vacío porque su imagen de pruebas lo tenía sin definir) → **ORA-65096** creando `lab4_local` sin prefijo en la raíz, **ORA-65094** creando `c##lab4_comun` desde FREEPDB1, y el usuario local en la PDB se crea sin más.
- **Ciclo completo:** `CREATE PLUGGABLE DATABASE pdb_lab4 FROM SEED` con `FILE_NAME_CONVERT` (PDB$SEED → carpeta propia): nace **MOUNTED**, `OPEN` → READ WRITE, sus 3 datafiles copiados en `/opt/oracle/oradata/FREE/PDB_LAB4/` y el servicio `pdb_lab4` registrado en el listener por LREG (el proceso que en la Parte H "registra los servicios"). Al borrarla: primero `DROP ... INCLUDING DATAFILES` → **ORA-65025** (está abierta), después `CLOSE IMMEDIATE` + `DROP`, queda `v$pdbs` sin ella y el script `rmdir`s la carpeta vacía → "Carpeta PDB_LAB4 eliminada". El script de borrado del guion trae el DROP antes del CLOSE a propósito: el error es el aprendizaje.

### Reto - Diseño del acceso de una auditor externa (no se ejecuta)

```sql
-- 1) Conectado a FREEPDB1 (la auditora solo audita ADMIN_CLINICA, no necesita la raíz)
CREATE USER auditor_ext IDENTIFIED BY "<generada-y-cifrada>";
-- 2) Mínimo para trabajar, todo en FREEPDB1:
GRANT CREATE SESSION TO auditor_ext;
GRANT READ ANY TABLE ON SCHEMA admin_clinica TO auditor_ext;
-- 3) Último día:
REVOKE READ ANY TABLE ON SCHEMA admin_clinica FROM auditor_ext;
REVOKE CREATE SESSION FROM auditor_ext;
DROP USER auditor_ext CASCADE;   -- el respaldo definitivo de la revocación
```

- **¿Común o local? ¿En qué contenedor?** **Local, en FREEPDB1.** Un común (`C##`) existe en todos los contenedores, obliga al prefijo, y le daría visibilidad de la raíz (I.2: el común sin CONTAINER_DATA de todas formas no ve las PDB, así que ni siquiera serviría "para algo"); la auditora solo necesita un piso. Como es local, ni puede hacer `SET CONTAINER` (necesitaría `GRANT SET CONTAINER`, que no se le da).
- **GRANT mínimo:** `CREATE SESSION` para entrar y `READ ANY TABLE ON SCHEMA admin_clinica` (23ai): el esquema completo, **incluidas las tablas que se creen durante la semana**, y nada más. En I.2 comprobé que el mismo privilegio dejó leer 20 000 filas de un esquema, no abrió el esquema vecino (ORA-00942) e impidió el `UPDATE` con **ORA-41900**. Sería equivalente conceder `SELECT` tabla a tabla (`cli_pacientes`, `cli_historias`, ...), pero hay que repetirlo con cada tabla nueva y se olvida: el privilegio de esquema evita el fallo silencioso de "me faltó una tabla".
- **Por qué no el catálogo:** `SELECT_CATALOG_ROLE` (que sí tiene `c##lab4_auditor` en I.2) abre todo el diccionario de la PDB: exceso para una auditoría de un esquema. Y nada de `SELECT ANY TABLE` (sin `ON SCHEMA`) ni de roles de escritura.
- **Revocación del último día:** `REVOKE` de los dos privilegios y `DROP USER ... CASCADE` como cierre; el revocar solo `CREATE SESSION` ya la dejaría sin acceso inmediato, pero el DROP garantiza que no quede una cuenta olvidada para siempre (misma lógica que el V003 de la Parte D).

### Preguntas tipo examen P13, P14 y P15

**P13: respuesta B (solo la fila de CON_ID 3).** `V$DATAFILE` se filtra por el contenedor de la sesión: en la raíz ve las 16 de los tres contenedores, dentro de FREEPDB1 solo sus 9. A incorrecta (no siempre muestra la CDB), C (CON_ID 0 es de redo/instancia, no de datafiles), D (`V$DATAFILE` existe en cualquier contenedor; la restricción es de visibilidad, no de existencia).

**P14: respuesta B (`ALTER USER c##audit SET CONTAINER_DATA = ALL ...`).** Es el atributo `CONTAINER_DATA` el que filtra las `CDB_`; `SELECT ANY DICTIONARY` no lo cambia, `SET CONTAINER` solo le deja entrar en cada PDB y mirar desde dentro, y abrir PDBs no quita el filtro de la cuenta.

**P15: respuestas A y D.** El privilegio de esquema es "todas las tablas del esquema, presentes y futuras" (A) y no se extrapola a otros esquemas (D). B falsa (solo ese esquema), C falsa (lectura; el `UPDATE` da ORA-41900, lo vi en I.2), E falsa (funciona con usuarios locales, `lab4_analista` lo es).

Evidencias: `10-que-ve-cada-usuario.script.log`, `10-ciclo-vida-pdb.script.log` y el spool `10-diccionario`.
