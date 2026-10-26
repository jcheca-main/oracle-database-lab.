# Bitácora — Práctica 1: Laboratorio 5 · Oracle DBA Workflow II

**Asignatura:** Administración de Bases de Datos · **Profesor:** Dr. Richard Avilés López
**Entregable:** PR fusionado con `scripts/lab5/`, migraciones `V004` y `V005`, evidencia `00`–`16` y respuestas.
**Issue:** [#5](https://github.com/jcheca-main/oracle-database-lab./issues/5) · **Rama:** `chore/5-oracle-dba-workflow-ii`

Modo de trabajo: ejecuto cada parte en el entorno (`oralab-26ai`, Oracle 26ai Free) y respondo las preguntas de comprobación citando mi propia evidencia (nombre de archivo y valor medido). Una respuesta sin cifra propia no puntúa.

---

## Parte A — Punto de partida, copia del Lab 4, Issue y branch

**Arranque.** Parto de `main` con el Lab 4 fusionado y etiquetado (`lab3-final`, `lab4-final`); `16-verificacion-final.sh` en **TODO OK**. Creo el Issue **#5** (el #4 lo ocupó el PR del Lab 4) y la rama `chore/5-oracle-dba-workflow-ii`.

**Copia en frío (evidencia 00).** `bash scripts/ops/backup-estado.sh lab4-final` → `backups/20261026T203457Z_lab4-final`, 632 MB comprimidos con manifiesto SHA-256. La base se para (`SHUTDOWN IMMEDIATE`), se copia el volumen y el script la rearranca (`esperar-healthy.sh`): termina en CDB/PDB `READ WRITE`, exit 0.

> **P1 · Compara el paso 6 de tu copia `lab4-final` con el de la copia `lab3-final`. ¿Qué demuestra la diferencia?**
>
> En la copia **lab3-final** (Lab 3) el paso «Cobertura / Archivos fuera del volumen» listó **5 datafiles FUERA** del volumen Docker (`/home/<user>/oralab-26ai-datos/...`): copiar solo el volumen no bastaba, había que arrastrar además esos cinco ficheros huérfanos a mano. En mi copia **lab4-final** (evidencia `20261026T203453Z_00-backup-lab4.script.log`, paso 3) los **26 archivos** (11 datafiles, 3 tempfiles, 3 redo, 2 control, spfile, pwfile) aparecen como `dentro` y **0 como `FUERA`**.
>
> **Demuestra** que la reubicación del Lab 4 (mover datafiles, spfile, pwfile y control al volumen `/opt/oracle/oradata`) consolidó todos los ficheros de la base dentro del volumen: ahora **una única copia en frío del volumen captura una imagen completa y consistente**, sin ficheros sueltos que recordar. Es la prueba visible en la propia salida del backup.

---

## Parte B — El banco de pruebas TiendaSur y la herramienta de medida

**El banco (migración V004).** `scripts/lab5/01-banco-tiendasur.sh` aplica `V004__banco_tiendasur.sql`: tablespace BIGFILE `tbs_tiendasur` (256 MB → 2 GB), esquema `tiendasur` **sin contraseña** (se administra desde cuentas con privilegios), y las tablas `cliente` (100 000 filas) y `pedido` (1 000 000 filas) con las proporciones de la Actividad 3.2. Los datos son **deterministas** (`ORA_HASH`, sin `DBMS_RANDOM`), así que todos los alumnos medimos lo mismo (benchmark reproducible). Crea los índices heredados (`ux_cli_email`, `ix_cli_pais_ciudad`, `ix_ped_cliente`, `ix_ped_fecha`, `ix_ped_importe`, `fk_ped_cliente`) y **histogramas** en `pais`, `ciudad`, `estado` y `canal`. Evidencia: `01-V004__banco_tiendasur.spool.log`, `01-perfil-tiendasur.script.log`.

**La herramienta (`lab_tools.medir`).** Paquete instalado en el esquema de herramientas `LAB_TOOLS` (sin contraseña): el código de laboratorio no vive en `SYS` ni en `TIENDASUR` (separación de responsabilidades). Usa **derechos de definidor** (`AUTHID DEFINER`, con los privilegios de `LAB_TOOLS`) y **privilegios de esquema 23ai** (`GRANT ... ANY TABLE ON SCHEMA tiendasur`), que alcanzan a `TIENDASUR` y a nada más (mínimo privilegio). `medir.consulta` ejecuta cada sentencia **dos veces y mide la segunda**; `medir.dml` mide bloques modificados y redo y deshace con `ROLLBACK`. Evidencia: `01-herramienta-medir.script.log` (`prueba_pk` → 1 lectura lógica, 0 físicas, plan `TABLE ACCESS BY INDEX ROWID PEDIDO > INDEX UNIQUE SCAN PK_PEDIDO`).

Medidas del perfil: **CLIENTE** bfr **66** (100 000 filas / 1 517 bloques, `avg_row_len` 102 B); **PEDIDO** bfr **188** (1 000 000 filas / 5 320 bloques, `avg_row_len` 32 B). Reparto de `estado`: C 90,2 % · D 2,8 % · E 5 % · **P 2 %**.

> **P2 · Calcula el bfr de CLIENTE y de PEDIDO con sus estadísticas. ¿Por qué PEDIDO cabe casi el triple de filas por bloque?**
>
> `bfr = NUM_ROWS / BLOCKS`: CLIENTE 100 000/1 517 = **66**; PEDIDO 1 000 000/5 320 = **188** (evidencia `01-perfil-tiendasur.script.log`). Y se cumple la fórmula de la Unidad 3, `b = ⌈r/bfr⌉`: ⌈1 000 000/188⌉ = 5 320 bloques.
>
> Un bloque son 8 192 B, luego las filas que caben ≈ (8 192 − cabecera) / longitud media de fila. Las filas de PEDIDO son mucho más cortas: `avg_row_len` **32 B** frente a **102 B** de CLIENTE (102/32 ≈ 3,2). CLIENTE arrastra columnas anchas (`email` VARCHAR2(120) → 26 B, `apellidos` VARCHAR2(80) → 19 B, más `nombre`, `dni`, `telefono`, `ciudad` 11 B); PEDIDO es casi todo fijo y estrecho (`id` 5, `id_cliente` 5, `fecha` 7, `estado` 1, `importe` 5, `canal` 1, `cp` 6 ≈ 32 B). Por eso 188/66 ≈ 2,85 ≈ triple: **depende del tamaño de fila, no del número de columnas**.

> **P3 · ¿Por qué el banco de medida ejecuta cada sentencia dos veces y mide solo la segunda?**
>
> La primera ejecución paga los costes únicos: **parse y optimización** (shared pool) y **fallos fríos de la caché** (lecturas físicas para traer los bloques al *buffer cache*). La segunda mide el estado **estable**: la sentencia ya está parseada y los bloques ya están en memoria (0 lecturas físicas), de modo que solo quedan las **lecturas lógicas (buffers)**, la métrica repetible. El tiempo parpadea (caché del sistema operativo, carga del portátil) pero las lecturas lógicas no: por eso un banco serio mide «en caliente», igual que en el Lab 4 fijamos que 1 lectura lógica ≈ 2 µs.

> **B1 (tipo examen) · Un plan real muestra E-Rows = 25 000 y A-Rows = 20 en el paso de acceso por índice sobre `estado`. ¿Cuál es la causa más probable?**
>
> **B. Faltan estadísticas con histograma en una columna de distribución sesgada.** `estado` está sesgada (C 90,2 %, E 5 %, D 2,8 %, P 2 %). Sin histograma el optimizador aplica la selectividad por defecto 1/NDV = 1/4 = 25 %, así que «adivina» unas 25 000 filas cuando el valor real de un estado raro es muchísimo menor (A-Rows = 20). No es fragmentación (A) ni filas migradas (C), que no alteran la estimación de cardinalidad; y si la consulta no fuera sargable (D) directamente no usaría el índice. En el Lab 5 lo comprobé al revés: con el histograma FREQUENCY de `estado` el optimizador sí sabe que P = 2 % y C = 90 % (evidencia `01-perfil-tiendasur.script.log`, columna `HISTOGRAM = FREQUENCY`).

> **Reto profesional · Filas por bloque de PEDIDO con `DBMS_ROWID` (mínimo, media, máximo) frente a `NUM_ROWS/BLOCKS`. ¿Por qué no todos los bloques tienen las mismas filas?**
>
> Agrupando por `DBMS_ROWID.ROWID_BLOCK_NUMBER(ROWID)` (evidencia `01-reto-bfr.script.log`): **5 220 bloques** contienen filas, con **mín 2, media 191,6, máx 200**. El bfr teórico `NUM_ROWS/BLOCKS` = 1 000 000/5 320 = **188**.
>
> Difieren porque `DBA_TABLES.BLOCKS` (5 320) cuenta todos los bloques reservados hasta el *high-water mark*, incluidos **~100 que hoy no guardan filas**; promediando solo sobre los 5 220 que sí las tienen: 1 000 000/5 220 = **191,6**. No todos los bloques llevan el mismo número de filas porque (1) un bloque se llena hasta no caber más → **máx 200** (bloque completo); (2) las filas son de **longitud variable**, así que cabe un número distinto en cada uno; (3) el **último bloque** de la carga directa `INSERT /*+ APPEND */` queda a medio llenar → el **mín 2**; (4) los bloques por encima del HWM se cuentan en `BLOCKS` pero están vacíos.
