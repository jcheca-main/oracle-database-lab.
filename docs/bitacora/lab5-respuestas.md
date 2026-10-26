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

## Parte C — Anatomía de un índice: altura, ramificación, raíz y hoja

**Lo que veo a nivel de comando.** El diccionario (`02-anatomia-indice.script.log`) da el resumen: `PK_CLIENTE` altura **2** / 187 hojas / CF 1477; `UX_CLI_EMAIL` altura **3** / 501 hojas; `IX_PED_CLIENTE` altura **3** / 2 216 hojas / CF 999 041; `PK_PEDIDO` altura **3** / 1 875 hojas / CF 5 220. `ANALYZE INDEX … VALIDATE STRUCTURE` (que **bloquea la tabla**: en producción solo en ventana de mantenimiento) rellena `INDEX_STATS`: para `IX_PED_CLIENTE`, fo real **370**, fo máx **543**, 451/503 entradas por hoja (90 %, `PCTFREE 10`).

**Lo que cuesta una búsqueda.** `GATHER_PLAN_STATISTICS` + `DISPLAY_CURSOR`: `WHERE id_pedido = 4711` devuelve `importe` con **4 Buffers** (altura 3 + 1 bloque de tabla); si solo pidiera `id_pedido` (columna que ya está en el índice), **3 Buffers** (no hay que ir a la tabla). Es la cuenta de la Unidad 3, medida por Oracle.

**Volcado byte a byte de `PK_CLIENTE`.** Raíz: `kdxconro 186` → 186 entradas + el hijo más a la izquierda (`kdxbrlmc`) = **187 hojas** (altura 2: la raíz apunta directo a las hojas). Hoja: `kdxconro 578`, `kdxcoavs 8` (solo 8 bytes libres → la PK se llenó al 100 % con claves crecientes), `kdxleprv 0` (es la primera hoja). Entrada `row#0 … data:(6) 00 00 03 1b 00 00` = ROWID de 6 bytes: bloque `0x31B` = 795, ranura 0; `col 0 … c1 02` = la clave (el número 1 en formato interno de NUMBER).

**Radiografía (`grafico-indice.sh`, solo lee, no bloquea).** `PK_PEDIDO` 99,9 % (mapa `#`), `IX_PED_CLIENTE` 89,7 % (mapa `=`), ambas uniformes: sin patrón cola.

> **P4 · Con tu evidencia 02: altura, nº de hojas y fan-out real de `IX_PED_CLIENTE`. ¿Qué altura tendría con mil millones de filas?**
>
> Evidencia `02-anatomia-indice.script.log`: altura **3**, **2 216 hojas**, **6 ramas** → fan-out **real** = (2 216 + 6 − 1)/6 = **370**; fan-out **máximo** = 8 028/14,8 = **543** (el límite físico, usado para predecir).
> Con **mil millones de filas** el propio script lo proyecta: 2 208 969 hojas → **altura 4** (1 + ⌈log₅₄₃(2 208 969)⌉ = 1 + 3). Solo **un nivel más** que ahora, aunque las filas crecen 1 000×: la altura crece con el **logaritmo**, no con el número de filas. Por eso pasar de 1 M a 20 M (la TiendaSur de la actividad) no la cambia (sigue en 3).

> **P5 · En el volcado de la hoja de `PK_CLIENTE`, localiza una entrada y descompón el ROWID. ¿Por qué no aparece el número de archivo?**
>
> Evidencia `02-volcado-indice.trc.txt` (hoja): `row#0[1200] … data:(6): 00 00 03 1b 00 00`, `col 0 … c1 02`. El ROWID «corto» de 6 bytes se descompone en **4 bytes de bloque** `00 00 03 1b` = `0x31B` = **bloque 795** y **2 bytes de ranura** `00 00` = **slot 0**. La clave `c1 02` es el número 1. Lo verifiqué contra la tabla: `SELECT … DBMS_ROWID.ROWID_BLOCK_NUMBER(ROWID,'BIGFILE') … WHERE id_cliente = 1` → bloque **795**, ranura **0** (coincide).
>
> **No aparece el número de archivo** porque `TBS_TIENDASUR` es un tablespace **BIGFILE**: tiene **un solo datafile**, así que el `file#` es implícito. El ROWID de bigfile usa 4 bytes para el bloque (direcciona hasta 4 000 M de bloques) y **omite** los 15 bits de archivo que lleva el ROWID «clásico» de smallfile.

> **C1 (tipo examen) · BLEVEL = 2. ¿Cuántas lecturas lógicas (mínimo) necesita una búsqueda por igualdad sobre la clave única que devuelve una columna que NO está en el índice?**
>
> **C. 4.** `BLEVEL = 2` son dos niveles de ramas; la altura = BLEVEL + 1 = **3** (raíz + rama + hoja). Bajar por el índice son 3 bloques de índice y, como la columna pedida no está en el índice, hay que ir a la tabla por el ROWID: **+1 bloque**. Total **3 + 1 = 4**. (Lo medí a mano en la Parte C: `WHERE id_pedido = 4711` pidiendo `importe` → 4 Buffers.)

> **C2 (tipo examen) · Índice con 2 000 000 de hojas y fan-out máximo 500. ¿Qué altura tendrá?**
>
> **C. 4.** altura = 1 + ⌈log_fo(hojas)⌉ = 1 + ⌈log₅₀₀(2 000 000)⌉ = 1 + ⌈2,34⌉ = 1 + 3 = **4**.

> **Reto profesional · Calcula antes de medir: altura de `UX_CLI_EMAIL` (100 000 entradas, 30 B/entrada, fo máx 543) y compárala con la medida.**
>
> **A mano** (con los supuestos del enunciado): entradas por hoja = ⌊7 996/30⌋ = 266 → hojas = ⌈100 000/266/0,9⌉ = **418** → altura = 1 + ⌈log₅₄₃(418)⌉ = 1 + 1 = **2**.
> **Medido** (`02-reto-ux-email.script.log`, `VALIDATE STRUCTURE`): altura **3**, **501 hojas**, **35,9 B** por entrada de hoja y **18,2 B** por entrada de rama → fo máx real = ⌊8 028/18,2⌋ = **441**.
> **Por qué el cálculo dijo 2 y la realidad es 3**: los dos supuestos eran optimistas. (1) La entrada de hoja real mide **35,9 B**, no 30 (el `email` es ancho) → **501 hojas**, no 418. (2) El fo máx **543** era el de `IX_PED_CLIENTE`, de clave NUMBER corta (14,8 B/entrada de rama); `UX_CLI_EMAIL` guarda un prefijo de email, sus entradas de rama pesan **18,2 B** y caben menos → fo **441**. Con fo 441 y 501 hojas: log₄₄₁(501) = **1,02 > 1** → ⌈ ⌉ = 2 ramas → **altura 3**. Un fo ~20 % menor bastó para cruzar 1,0 y subir un nivel entero: la altura depende del **tamaño real de la clave**, no solo del número de filas.
>
> **Mapa de `UX_CLI_EMAIL` frente a `PK_CLIENTE` (mismas 100 000 entradas).** Ambos mapas son **uniformes** (ninguno es patrón cola), pero la ocupación difiere: `PK_CLIENTE` llena sus hojas al **~100 %** (mapa `#`; el volcado daba `kdxcoavs 8`, 578 entradas) mientras `UX_CLI_EMAIL` se queda en **~90 %** (mapa `=`, `PCTFREE 10` intacto). La clave es **en qué orden llegaron las claves**: las de `PK_CLIENTE` (`id_cliente`) llegaron **crecientes** (la carga hizo `ORDER BY n`), así que cada insert apunta al extremo derecho → divisiones **90/10** → hojas empaquetadas al 100 %. Las de `UX_CLI_EMAIL` son `email = 'cliente' || n || '@…'`; cargadas en orden de id, los **strings de email no ordenan igual** que los números (`cliente1@` < `cliente10@` < `cliente100@`), así que las claves caen **dispersas** por el orden del índice → divisiones **50/50** → cada hoja se estabiliza en el 10 % que `PCTFREE` dejó libre.

## Parte D — Tipos de índice, medidos

**Experimento de laboratorio.** `03-tipos-indice.sql` crea cada tipo de índice para la consulta de la Actividad 3.2 que le corresponde, la mide con `lab_tools.medir.consulta` y **lo borra todo al final** (vuelve a quedar 7 índices): lo que se decida conservar entra por migración en la Parte G (V005). Todo cuadra con la ficha (evidencia `03-tipos-indice.script.log`): Q13 1486→3 (+ `ORA-00001`/`ORA-03301`), Q6 SKIP SCAN 144 vs 103, Q7 15→7→3, Q1 1486→4, Q12 246/2933 hojas vs 239/54 hojas, Q14 4073→528, Q15 4/3/1 (limpieza hash 2770).

> **P6 · Elige tres pruebas de la Parte D y explica, con las lecturas lógicas medidas, por qué un tipo de índice gana al otro.**
>
> **1. Único — Q13 por DNI (`03-tipos-indice.script.log`).** Sin índice: **1486 lecturas** (`TABLE ACCESS FULL CLIENTE`). Con `UX_CLI_DNI` UNIQUE: **3 lecturas** (`INDEX UNIQUE SCAN`). Gana el B-tree porque convierte un recorrido completo en 3 saltos (raíz/rama/hoja + tabla); y además, al ser UNIQUE, **la base de datos impide el duplicado**: el `INSERT` que repite el DNI devuelve `ORA-00001`, con el valor que choca (`ORA-03301`, novedad de 23ai).
>
> **2. Compuesto + cubriente — Q7 historial.** Con `IX_PED_CLIENTE`: **15 lecturas** y plan con `SORT ORDER BY` (hay que ordenar por fecha). Con `(id_cliente, fecha_pedido)`: **7 lecturas** y `INDEX RANGE SCAN DESCENDING` **sin SORT** (igualdad primero, rango después: el índice devuelve las filas ya ordenadas). Cubriendo la clave con las columnas pedidas: **3 lecturas** y ni siquiera se toca la tabla (`INDEX RANGE SCAN` solo). Ganan el prefijo izquierdo (quita el SORT) y la cobertura (quita el acceso a la tabla).
>
> **3. Clúster hash — Q15 token de sesión.** Montículo + PK: **4 lecturas**; IOT: **3** (la tabla *es* el índice, ahorra el salto); clúster hash: **1 lectura** (`TABLE ACCESS HASH`), porque la clave se convierte en la dirección del bloque. Gana el hash para la búsqueda puntual… **pero** su punto flaco aparece en la misma prueba: la limpieza por rango (`WHERE caduca < …`) no puede usar el hash y recorre la tabla entera: **2770 lecturas**. Cada tipo gana en su consulta y pierde en la que no le sirve.

> **D1 (tipo examen) · Tabla de hechos cargada de noche; los analistas filtran por region (6), canal (3) y anio (5). ¿Qué índice es más apropiado?**
>
> **B. Un índice bitmap en cada columna.** Es un **almacén de datos** (carga nocturna, sin escrituras concurrentes) con columnas de **baja cardinalidad** (6, 3 y 5 valores): el escenario exacto del experimento 6, donde `BITMAP AND` combinó los cuatro filtros en **528 lecturas** frente a **4073** del recorrido completo, y el bitmap de `region` ocupa **114 hojas** frente a **1954** del B-tree. Un B-tree compuesto (A) no combina bien filtros arbitrarios; el funcional (C) y el hash (D) no aplican.

> **D2 (tipo examen) · ¿Qué dos afirmaciones sobre un índice cubriente son correctas? (Elige dos.)**
>
> **A y C.** **A**: evita el acceso a la tabla si la consulta solo usa columnas del índice (lo medí en Q7: 3 lecturas, solo `INDEX RANGE SCAN`). **C**: encarece cada INSERT/UPDATE de sus columnas, porque hay que mantener el índice (y por eso el guion advierte que el cubriente es el más rápido… y el más grande: `IX_PED_CLI_FEC_CUB` 40 MB). **B** es falsa (suele ocupar tanto como la tabla); **D** es falsa (Oracle no tiene `INCLUDE`: las columnas «de regalo» se añaden al final de la clave); **E** es falsa (puede tener muchas columnas).

> **Reto profesional · Q9 (20 pedidos más recientes con todas sus columnas) usa `IX_PED_FECHA`. ¿Le añadirías columnas para hacerlo cubriente?**
>
> **No.** Medido (`03-reto-q9.script.log`): la versión actual cuesta **5 lecturas lógicas** (plan `COUNT STOPKEY > VIEW > TABLE ACCESS BY INDEX ROWID PEDIDO > INDEX FULL SCAN DESCENDING IX_PED_FECHA`), porque `STOPKEY` se detiene a las 20 filas.
> Para hacerlo cubriente, `Q9` hace `SELECT *`: haría falta un índice con **las 7 columnas** de `pedido`, es decir ≈ **42 MB** (tanto como la tabla entera, sección 8) y mantenido en **cada INSERT/UPDATE** de `pedido`, **para ahorrar esas 5 lecturas** de una consulta que solo devuelve 20 filas. **Decisión (una línea, dos números):** *no; 5 lecturas actuales frente a +42 MB de índice que cada escritura mantendría.* (En cambio, el cubriente de Q7 sí compensa: es la consulta más frecuente —2000/s— y solo necesita unas pocas columnas.)

## Parte E — Factor de agrupamiento y punto de equilibrio

**El CF es de la tabla, no del índice.** `04-agrupamiento-equilibrio.script.log`: `PK_PEDIDO` e `IX_PED_FECHA` CF **5220** (≈ los 5320 bloques) = **BUENO**; `IX_PED_IMPORTE` 998 078 y `IX_PED_CLIENTE` **999 041** (≈ los 1 000 000 filas) = **MALO**. Recorrer el índice a mano con `LAG` sobre el ROWID da **exactamente** el mismo número (5220 y 999 041), lo que demuestra que el CF es «cuántos bloques distintos leería si recorrera el índice entero».

> **P7 · ¿Por qué `IX_PED_FECHA` tiene el CF cercano a los bloques e `IX_PED_CLIENTE` cercano a las filas? ¿Lo arreglaría un `REBUILD`?**
>
> Porque `pedido` se cargó **en orden de `fecha_pedido`** (`INSERT /*+ APPEND */ … ORDER BY n`, y la fecha crece con `n`): dos filas vecinas en el índice por fecha están **en el mismo bloque** de tabla, así que el recorrido apenas cambia de bloque → CF ≈ nº de bloques (**5220**). En cambio `id_cliente` se repartió **al azar** (`ORA_HASH`): dos filas vecinas por cliente están **en bloques distintos**, casi cada salto de fila es un salto de bloque → CF ≈ nº de filas (**999 041**).
>
> **No, un `REBUILD` no lo arregla.** El CF mide el orden físico de las **filas en la tabla**, y el `REBUILD` solo reordena las claves del **índice**: el orden de las filas en disco no cambia, así que el recuento de cambios de bloque es idéntico. Lo que cambia el CF es reordenar la **tabla** (`MOVE` con `ORDER BY`, una IOT o un clúster) — y al reordenar por cliente **empeorarías** el CF de fecha: solo hay un orden físico.

> **P8 · Según tu curva, ¿a partir de qué porcentaje deja de compensar cada índice? Compáralo con la fórmula de la Unidad 3.**
>
> De mi curva (evidencia `04-agrupamiento-equilibrio.script.log`, sección 3; la tabla entera cuesta siempre **5232**):
> - **Índice con CF malo** (`IX_PED_CLIENTE`): sus lecturas superan a la tabla entera desde el **1 %** (9 920 > 5232). Pero **el optimizador** lo abandona antes, entre **0,1 %** y **0,2 %**.
> - **Índice con CF bueno** (`IX_PED_FECHA`): solo pierde al **100 %** (7 875 > 5232), porque lee bloques **consecutivos** (≈ k/bfr).
>
> **Fórmula (Unidad 3, 3.1.8):** con CF malo, cada fila es una lectura aleatoria, así que el índice compensa si `k/r < (1/bfr)·(c_sec/c_aleat)`. Con bfr = 188: en **lecturas lógicas** (`c_sec = c_aleat`), `k/r < 1/188 = 0,53 %`; **en disco** (`c_sec/c_aleat = 1/5`), `k/r < 0,11 %`. El cambio del optimizador (0,1–0,2 %) coincide con la predicción **en disco** (0,11 %): su modelo de coste asume que la lectura aleatoria es ~5× más cara que la multibloque, por eso se rinde antes de lo que dirían las lecturas lógicas crudas (1 %).

> **E1 (tipo examen) · CF = 9 950 000 sobre 10 000 000 filas y 80 000 bloques; se pide el 3 % por ese índice. ¿Plan razonable?**
>
> **B. Recorrido completo de tabla.** El CF (9,95 M) está pegado a las filas (10 M) = **agrupamiento malo**: cada fila del índice es un bloque distinto, así que el 3 % (300 000 filas) costaría ~300 000 lecturas aleatorias, frente a **80 000** del recorrido completo. Con la fórmula: bfr = 10 M/80 000 = 125 → el índice compensa si `k/r < 1/125 = 0,8 %`; el 3 % **supera** el 0,8 %, así que el recorrido completo es más barato. Reconstruir (C) no mejora el CF (ver P7) y un bitmap (D) no sirve para una recuperación por ROWID.

> **Reto profesional · Dibuja la curva del punto de equilibrio (escala log) y explica por qué los tres puntos no coinciden.**
>
> Curva medida (lecturas lógicas; tabla entera = 5232, `o` = índice CF bueno, `x` = índice CF malo, `-` = tabla entera, `+` = cruce):
>
> ```
>          |           x
>  5e+05   |
>          |          x
>          |         x
>          |        x
>  4e+04   |       x
>          |      x
>          |
>          |-----*-----+      <- tabla entera (5232)
>  3e+03   |    x     o
>          |   x     o
>          |  x     o
>          | x     o
>  2e+02   |
>          |x     o           <- el malo (x) ya supera a la tabla hacia 1%
>          |     o
>          |    o
>  1e+01   |   o
>          |  o
>          |oo                <- el bueno (o) sigue muy por debajo
>  1e+00   |
>          +----------
>           .0  .1  .5  2  10  50
>           k% (escala log)
> ```
>
> **Por qué los tres puntos no coinciden (tres líneas):**
> 1. El **CF malo** cruza la línea de la tabla pronto (~1 %) y el **CF bueno** casi nunca (~100 %): es el mismo tipo de índice, pero el CF bueno lee bloques **consecutivos** (≈ k/bfr) y el malo salta a un bloque **distinto por fila** (≈ k).
> 2. El **optimizador** cambia aún más temprano (0,1–0,2 %) porque su modelo de coste valora la lectura **aleatoria ~5×** la multibloque (`c_sec/c_aleat = 1/5`), no usa el recuento crudo de lecturas lógicas.
> 3. Por eso los tres puntos son distintos: el cruce del índice malo (~1 %, lecturas crudas), el del bueno (~100 %) y el del optimizador (~0,11 %, ponderado a disco) difieren por el **orden físico de las filas** (agrupamiento) y por el **peso del coste** del acceso aleatorio.
