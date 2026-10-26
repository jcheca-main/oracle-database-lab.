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

## Parte F — Sargabilidad: consulta rota frente a consulta reescrita

**Las cinco reglas, medidas** (`05-sargabilidad.script.log`). La columna indexada debe quedar **desnuda** a un lado del operador:
- **Regla 1 (función):** `UPPER(email)=…` **1486** (completo) → `email=LOWER(…)` **4** (usa `UX_CLI_EMAIL`).
- **Regla 2 (aritmética):** `fecha+INTERVAL '30' DAY>=…` **5285** → despejar `fecha>=…−30` **320** (rango en `IX_PED_FECHA`).
- **Regla 3 (conversión implícita):** `codigo_postal=30001` (VARCHAR2 vs NUMBER) **5232** → `'30001'` **106**. La prueba del delito está en el plan: `filter(TO_NUMBER("CODIGO_POSTAL")=30001)`.
- **Regla 4 (comodín izquierdo):** `LIKE '%ez'` recorrido completo (1523); `LIKE 'Gonz%'` índice (2024).
- **Regla 5 (OR):** `email=:t OR telefono=:t` sin índice en `telefono` **1486** → con índice en las dos ramas (BITMAP OR) o `UNION` **6**.
- **Bonus Q11:** `EXTRACT(YEAR…)=2025` y el rango de fechas **ambos** hacen recorrido completo (5232): un año es 1/3 de los pedidos, está muy por encima del punto de equilibrio. **Sargable no significa «usa el índice»**.

> **P9 · ¿Por qué Q4b (`'Gonz%'`) usa el índice y aun así lee más bloques que un recorrido completo?**
>
> `LIKE 'Gonz%'` **es** sargable: el comodín va al final, así que es un **rango** sobre el principio de la cadena y el optimizador puede usar `IX_CLI_APELLIDOS` (medido: `INDEX RANGE SCAN`, 2024 lecturas). Pero `apellidos` en `cliente` tiene **agrupamiento malo** (los clientes se cargaron en orden de id, los apellidos llegaron dispersos por `ORA_HASH`): cada una de las ~2056 filas `Gonz%` está en un **bloque distinto**, así que seguirlas por el índice toca ~2024 bloques, frente a los **1517** de un único barrido secuencial de la tabla. El 2,1 % de filas con CF malo está **muy por encima** del punto de equilibrio de la Parte E (~0,11 %): lo correcto ahí es el recorrido completo. El índice **puede** usarse; no **debe**.

> **F1 (tipo examen) · `num_factura` VARCHAR2(10) con índice. ¿Qué predicado impide usarlo?**
>
> **B. `num_factura = 2025001`** (literal **número** contra VARCHAR2). Oracle aplica **siempre** la conversión a la **columna** (`TO_NUMBER(num_factura)`), nunca al literal, y el índice queda inutilizado → recorrido completo. Es la regla 3, que medí en Q3 (`filter(TO_NUMBER("CODIGO_POSTAL")=30001)`). **A** (cadena), **C** (`LIKE '2025%'`, rango) y **D** (`BETWEEN` de cadenas) dejan la columna desnuda y sí usan el índice.

> **F2 (tipo examen) · ¿Qué dos reescrituras convierten `WHERE TRUNC(fecha) = DATE '2026-10-18'` en una condición sargable equivalente? (Elige dos.)**
>
> **A y C.** **A**: `fecha >= DATE '2026-10-18' AND fecha < DATE '2026-10-19'` (despeja el `TRUNC` como un rango de día completo). **C**: `fecha BETWEEN DATE '2026-10-18' AND DATE '2026-10-18' + INTERVAL '86399' SECOND` (el día entero como rango). **B** (`fecha = DATE '2026-10-18'`) solo cogería la medianoche exacta si `fecha` lleva hora; **D** (`TO_CHAR(fecha,…)=…`) y **E** (`fecha+0=…`) envuelven la columna en función/aritmética: no son sargables.

> **Reto profesional · Revisión de código del PR del compañero.**
>
> Consulta propuesta: `SELECT * FROM tiendasur.cliente WHERE SUBSTR(telefono,1,3)='600' OR UPPER(apellidos)='GIL'`.
>
> **Comentario de revisión:** «Rompe la **regla 1** dos veces: `SUBSTR(telefono,1,3)` y `UPPER(apellidos)` envuelven la columna, así que **ninguna** rama puede usar un B-tree; y al ser un **OR** (regla 5) donde **ninguna** rama es indexable, Oracle hace **recorrido completo** (medido: **1487 lecturas**, evidencia `05-reto-revision.script.log`). Además hay un **bug de negocio**: `apellidos` guarda **dos palabras** (`'González Gil'`), luego `UPPER(apellidos)='GIL'` **no casa con nada** (medido: **0 filas**); si buscabas el apellido `Gil`, eso no es una reescritura sino Text o un índice — dímelo y lo diseñamos. **Reescritura:** despeja el teléfono a **rango de prefijo** `telefono >= '600' AND telefono < '601'` (sargable, usa el índice) y, si de verdad necesitas la rama de apellidos, decide primero la semántica.»
>
> **Medido antes/después** (con los índices `ix_cli_telefono`/`ix_cli_apellidos` recreados y luego borrados):
> - **Rota:** 981 filas, **1487 lecturas**, `TABLE ACCESS FULL CLIENTE`.
> - **Reescrita** (`(telefono>='600' AND telefono<'601') OR apellidos='Gil'`): 981 filas, **722 lecturas**, `BITMAP OR` sobre los dos índices.
>
> La reescritura baja de 1487 a 722, pero no a unas pocas lecturas: los 981 teléfonos que empiezan por `600` están **dispersos** (agrupamiento malo en `telefono`), así que seguir el índice toca cientos de bloques. Ganancia real, pero deja claro que la ramificación de apellidos no aporta nada (0 filas).

## Parte G — Protocolo de diseño de índices y coste de escritura (V005)

**Ningún índice es gratis.** `06-indices.script.log` mide el coste de escribir en los tres escenarios: **hoy** (4 índices) INSERT **10,1 bloques/fila** y 1305 B de redo; **con la propuesta del compañero** (5 índices más → 9) **20,2 bloques/fila** (el doble de trabajo por escritura); **con V005** (5 índices) **12,1 bloques/fila**. Cada índice son ~2 bloques modificados por INSERT (la hoja y su undo).

**El protocolo de cinco preguntas, con números:**
1. **Necesidad** (`MONITORING USAGE`): la carga habitual (Q2, Q3, Q7, Q8, Q9, Q12) marca **sin uso** `IX_PED_CANAL`, `IX_PED_CLIENTE`, `IX_PED_FEC_CLI` e `IX_PED_IMPORTE`; en uso `IX_PED_CLI_FEC`, `IX_PED_CP`, `IX_PED_ESTADO`, `IX_PED_FECHA`. En producción la ventana es de **semanas** (con cierres de mes); 23ai guarda además `DBA_INDEX_USAGE` (~15 min de retraso).
2. **Viabilidad**: `canal` (3 valores, 33 %) y `estado` (4, 25 %) están **muy por encima** del umbral (~0,5 %): no viables para igualdad. `cp` (0,009 %), `importe` (0,002 %) y `cliente` (0,001 %) sí.
3. **Escritura**: ver arriba (10,1 → 20,2 con la propuesta).
4. **Redundancia** (`DBA_IND_COLUMNS`): `IX_PED_CLIENTE` es prefijo de `IX_PED_CLI_FEC` y `IX_PED_FECHA` de `IX_PED_FEC_CLI`: sobra uno de cada pareja. (Un índice **único** no es redundante aunque sea prefijo; y la clave ajena `id_cliente` **siempre** necesita un índice que empiece por ella, o cada DELETE de un cliente bloquea `PEDIDO` entero.)
5. **Ciclo de vida**: `IX_PED_IMPORTE` se pone **INVISIBLE** y la carga sigue igual (Q2: 333 lecturas); si en la observación nadie lo echa de menos, se borra por migración.

**V005 (la decisión versionada).** Crea `ux_cli_dni` (Q13, garantiza unicidad), `ix_ped_cli_fec_cub` (Q7 cubriente), `ix_ped_pendientes` (parcial, solo 2 %, sobre columna virtual `fecha_pendiente`), `ix_ped_cp` (Q3 reescrita); **borra** `ix_ped_cliente` (prefijo del cubriente) e `ix_ped_importe` (cero usos). Todo `ONLINE` e idempotente (comprueba `ux_cli_dni`). Al final: 9 índices (CLIENTE 4, PEDIDO 5).

> **P10 · Con tu evidencia 06: bloques modificados por INSERT con 4, 9 y 5 índices. ¿Qué índices de la propuesta del compañero rechazaste y con qué dato?**
>
> INSERT por fila: **10,1** bloques (4 índices) → **20,2** (9 índices, la propuesta) → **12,1** con V005 (5 índices). Evidencia `06-indices.script.log`.
> De los cinco propuestos **rechacé tres**:
> - **`canal`**: sin uso en la observación (P1) y selectividad **33 %** por valor (P2), muy por encima del ~0,5 %: nunca viable para igualdad.
> - **`estado`** para igualdad: selectividad **25 %** (P2); el único valor que interesa, `P` (2 %), se sirve mejor con el índice **parcial** `ix_ped_pendientes` de V005.
> - **`(fecha, id_cliente)` (`IX_PED_FEC_CLI`)**: **redundante** (P4) — `IX_PED_FECHA` ya es su prefijo izquierdo — y sin uso (P1).
> Y del conjunto existente **borré** `ix_ped_cliente` (prefijo del cubriente `ix_ped_cli_fec_cub`, que sigue cubriendo la clave ajena) e `ix_ped_importe` (cero usos). Los que sí sobrevivieron: `(id_cliente, fecha)` como cubriente y `codigo_postal`.

> **G1 (tipo examen) · ¿Cómo comprobar si un índice se sigue necesitando antes de borrarlo, sin dejar de mantenerlo y con marcha atrás al instante?**
>
> **B. `ALTER INDEX ... INVISIBLE`.** El optimizador lo ignora pero Oracle **lo sigue manteniendo** (sigue pagando el coste de escritura); si algo empeora, `ALTER INDEX ... VISIBLE` lo devuelve en un segundo, sin reconstruir nada. `UNUSABLE` (A) lo deja inservible y sin mantener, `DROP` (C) no tiene marcha atrás instantánea y `NOLOGGING` (D) no afecta al uso.

> **G2 (tipo examen) · Tabla con 3 índices B-tree y 500 INSERT/s. ¿Cuántos bloques/s añade un cuarto índice?**
>
> **B. Unos 1000.** Medido en la Parte G (P3): cada índice suma **~2 bloques modificados por INSERT** (la hoja que se divide/modifica y su undo). 500 INSERT/s × 2 = **1000 bloques/s** de más. (Y esos bloques se escriben en redo y en undo, y hay que hacerles un `DROP` o un `REBUILD` más adelante.)

> **Reto profesional · Defiende tu propio índice (V006) para una consulta que V005 NO cubre.**
>
> **Consulta:** Q4b — `SELECT id_cliente, nombre, apellidos FROM tiendasur.cliente WHERE apellidos LIKE 'Gonz%'` (V005 no cubre `apellidos`). **Propuesta:** `ix_cli_apellidos` sobre `(apellidos)`. Evidencia `06-reto-v006.script.log`.
>
> **Las cinco preguntas con números del banco:**
> 1. **Necesidad**: es una búsqueda real (localizar por apellido en la aplicación).
> 2. **Viabilidad**: `Gonz%` son **2056 filas** = **2,1 %** de `cliente`, por encima del umbral de equilibrio (~0,5 % de la Parte E).
> 3. **Escritura**: con el índice, un INSERT cuesta **14 bloques/fila** (≈ +2 por el índice, para siempre).
> 4. **Redundancia**: **no** redundante (ningún otro índice cubre `apellidos`).
> 5. **Ciclo de vida**: n/a (índice nuevo).
>
> **Medido antes/después:** sin índice **1490 lecturas** (`TABLE ACCESS FULL`); con `ix_cli_apellidos` **2024 lecturas** (`INDEX RANGE SCAN`). El **CF del propuesto es 84964** frente a los **1517 bloques** de `cliente` = **agrupamiento malo**.
>
> **Conclusión (una respuesta profesional): NO compensa.** El índice lee **más** que el recorrido completo (2024 > 1490): los 2056 `Gonz%` están **dispersos**, así que seguirlas por el índice toca ~2024 bloques distintos, frente a un único barrido secuencial de 1490. Y encima **añade ~2 bloques de escritura por INSERT**. Por eso lo **documenté y NO fusioné** V006; lo correcto para `Gonz%` sigue siendo el recorrido completo (o, si el apellido es crítico, un reparto distinto del dato, no un índice por encima).

## Parte H — Divisiones de hoja, patrón cola y remedios

**Cómo crece un índice** (`07a-crecimiento.script.log`, 200 000 altas por tabla). Con `V$MYSTAT` (`leaf node splits` / `leaf node 90-10 splits`) y `grafico-indice.sh`:
- **AZAR** (claves aleatorias): **595 divisiones, 0 son 90/10**, llenado **75 %** (mapa `=`/`-`/`#` mezclado). Es el estado estable de un B-tree con inserciones aleatorias: la teoría (Unidad 3) predice ~69 % (ln 2) y aquí se mide 75 %.
- **CRECIENTE** (secuencia/fecha): **398 divisiones, las 398 son 90/10**, llenado **100 %** (mapa todo `#`). La hoja de la derecha se llena y Oracle abre una nueva casi vacía, dejando la vieja completa.
- **REVERSE** (claves invertidas): 511 divisiones, 0 son 90/10, 78 %. **Su precio**: el rango `k BETWEEN 1000 AND 1100` con el índice normal cuesta **4 lecturas**; con REVERSE, **878** (recorrido completo) — el índice ya no está ordenado por la clave.

**El patrón cola** (`07b-patron-cola.script.log`): entran 200 000 mensajes, se **borran los 150 000 más antiguos**, entran 50 000 más. Síntoma: «dame el siguiente mensaje» (el más antiguo) cuesta **238 lecturas** frente a **2** del índice sano, porque el índice baja a la hoja más a la izquierda y la encuentra **vacía**, y la siguiente… hasta la primera entrada viva. `INDEX_STATS`: **437 hojas**, **75 236 borradas (43 %)** que aún ocupan sitio, 236 hojas vacías. **`DBA_INDEXES.LEAF_BLOCKS` no lo ve** (lo rellena `DBMS_STATS` y no cuenta vacías): hacen falta `VALIDATE STRUCTURE` o el gráfico.

**Remedios medidos** (`07c-remedios.script.log`): COALESCE **238 → 2 lecturas** (437 → 201 hojas, en línea, no devuelve espacio); SHRINK SPACE **238 → 2** y devuelve el espacio (**4 → 1,69 MB**, baja la marca de agua); REBUILD ONLINE 223 hojas pero necesita **espacio doble** y mucho redo. La cura de verdad es de **diseño**: particionar por fecha y vaciar particiones enteras.

> **P11 · Distingue, con tus gráficos de la Parte H, un índice con divisiones 50/50, uno con 90/10 y uno con patrón cola.**
>
> - **50/50 (`IX_AZAR`)**: histograma **repartido** entre el 40 % y el 99 % (pico en 80-89 %), ocupación media **75 %**, mapa **mezclado** (`= - #` a lo largo). Ninguna hoja al 100 %: las divisiones parten las hojas por la mitad y quedan a medias.
> - **90/10 (`IX_CRECIENTE`)**: histograma **concentrado** en 90-99 % (398 hojas), ocupación **99,9 %**, mapa **todo `#`**. Divisiones 90/10 (398 de 398): la hoja derecha se llena y se abre una nueva.
> - **Patrón cola (`IX_COLA`)**: histograma **bimodal** — 236 hojas al 0-9 % **y** 199 al 90-99 % — mapa **vacío a la izquierda y lleno a la derecha** `[   ...####]`, y `del_lf_rows` alto (75 236, 43 %). Es el sello: se inserta por la derecha y se borra por la izquierda.

> **H1 (tipo examen) · Tabla de eventos con claves crecientes y purga nocturna de >30 días; «evento más antiguo» se ha vuelto lenta. ¿Acción en línea y de menor coste?**
>
> **B. `ALTER INDEX ... COALESCE`.** Es el patrón cola (medido: 238 lecturas). El COALESCE **fusiona las hojas vecinas medio vacías** en línea y sin bloqueo, y resuelve el síntoma por **2** lecturas (medido: 238 → 2). El REBUILD (A) también lo arregla pero cuesta espacio doble y mucho redo; el REVERSE (C) no ayuda a las lecturas; `GATHER_INDEX_STATS` (D) solo actualiza el diccionario, no repara las hojas vacías físicas.

> **H2 (tipo examen) · ¿Qué dos afirmaciones sobre un índice REVERSE son correctas? (Elige dos.)**
>
> **A y C.** **A**: reduce la contención en la hoja más a la derecha con claves crecientes (dispersa las claves consecutivas). **C**: no puede usarse para un rango (`BETWEEN`) sobre la clave, porque el índice ya no está ordenado por ella — medido: el rango cuesta **878 lecturas** (recorrido completo) frente a **4** del índice normal. **B** es falsa (los rangos son más lentos, no más rápidos), **D** falsa (el CF es una propiedad de la **tabla**), **E** falsa (sigue habiendo divisiones: 511).

> **P12 · ¿Qué remedio elegirías para el patrón cola en producción, en horario de servicio, y por qué?**
>
> **`ALTER INDEX ... COALESCE`.** Es el único que resuelve el síntoma **en línea y con el menor coste**: fusiona las hojas vecinas medio vacías sin reconstruir, sin necesitar **espacio doble** ni generar el redo masivo del `REBUILD ONLINE` (peligroso en hora punta). Medido: **238 → 2 lecturas** y 437 → 201 hojas, sin bloquear las escrituras. El `SHRINK SPACE` también funciona en línea y además devuelve el espacio (4 → 1,69 MB), pero si solo quieres quitar el síntoma, el COALESCE es la mínima intervención. El `REBUILD` se reserva para una causa concreta y medida. Y la **cura de verdad** —particionar por fecha y vaciar particiones enteras— es un cambio de **diseño**, que se saca del horario de servicio.

> **Reto profesional · Diagnostica sin ver el script (con `grafico-indice.sh` + `INDEX_STATS`) y justifica con dos cifras antes/después.**
>
> **Diagnóstico: PATRÓN COLA** (evidencias `07b-patron-cola.script.log` y `07b-grafico-IX_COLA-antes.script.log`).
> - **Por el gráfico**: el mapa está **vacío a la izquierda y lleno a la derecha** `[   ...####]`, con el histograma **bimodal** (236 hojas al 0-9 % + 199 al 90-99 %). Ese es el sello de la cola; no es un 50/50 sano (histograma repartido) ni un 90/10 (todo al 100 %).
> - **Por `INDEX_STATS`**: **437 hojas** pero **75 236 borradas (43 %)** y 236 **vacías**; ocupación viva 45,8 % mientras el segmento está al 80 %.
> - **Síntoma que lo confirma**: «dame el siguiente mensaje» (clave más baja) = **238 lecturas** para **1 fila**.
>
> **Remedio y dos cifras antes/después**: `COALESCE` (en línea, el más barato). **Lecturas del siguiente mensaje: 238 → 2. Hojas: 437 → 201.** (`SHRINK SPACE` haría lo mismo y además devolvería el espacio: 4 → 1,69 MB; el REBUILD es desproporcionado aquí.)

## Parte I — SCN y checkpoints: el reloj de la base

**Empieza la durabilidad.** `08-scn-checkpoint.script.log`:
- **El SCN solo sube**: dos lecturas seguidas de `v$database.current_scn` dan 5322308 y 5322309 — hay actividad interna aunque nadie haga nada.
- **Sincronización control file / cabeceras**: el checkpoint en el control file (`v$datafile.checkpoint_change#`) y el de la cabecera de cada archivo (`v$datafile_header.checkpoint_change#`) coinciden → `sincronizado`. `PDB$SEED` (con_id 2) se queda en 2098101 porque está en **solo lectura**: su checkpoint no avanza.
- Tras un `UPDATE` + `ALTER SYSTEM CHECKPOINT`, los archivos abiertos pasan al SCN nuevo (5322314): `DBWn` escribió los bloques sucios y `CKPT` apuntó el SCN en ambos sitios.
- **MTTR**: `estimated_mttr` **26 s** con `actual_redo_blks` **429383** pendientes; `fast_start_mttr_target` = 0, `log_checkpoint_timeout` = 1800.

> **P13 · Con tu evidencia 08: ¿qué valores compara Oracle al abrir para decidir si hace falta recuperación?**
>
> Compara el **SCN de checkpoint del control file** con el **SCN de la cabecera del propio datafile**: `v$datafile.checkpoint_change#` (lo que el control file cree que tiene cada archivo) frente a `v$datafile_header.checkpoint_change#` (lo que dice la cabecera del archivo). En mi evidencia `08-scn-checkpoint.script.log` los dos valen **5314307** en todos los archivos abiertos → `sincronizado`, **no hace falta recuperación**. Si no coinciden, ese archivo necesita recuperación (Oracle aplica redo desde el checkpoint hasta el SCN de la cabecera). `PDB$SEED` está por detrás (2098101) pero es normal: está en solo lectura.

> **I1 (tipo examen) · Al abrir la base, ¿qué compara Oracle para decidir si un datafile necesita recuperación?**
>
> **B. El SCN de checkpoint del control file con el de la cabecera del datafile.** Es exactamente lo que midí en la P13 / evidencia 08 (`v$datafile.checkpoint_change#` vs `v$datafile_header.checkpoint_change#`). No es el tamaño (A), ni la fecha del SO (C), ni los bloques sucios del buffer cache (D).

> **Reto profesional · El MTTR bajo carga.**
>
> Con la base en marcha, antes del UPDATE: `estimated_mttr` **26 s**, `actual_redo_blks` **429736**. Hice un `UPDATE` de **20 000 filas** sobre `pedido` (y `COMMIT`, **sin** checkpoint) y volví a medir (`08-reto-mttr.script.log`): `estimated_mttr` **36 s** (+10) y `actual_redo_blks` **436858** (+7122 bloques de redo).
> **Relación en una frase**: cada bloque de redo pendiente es trabajo que la recuperación de instancia tendrá que **replayar** desde el último checkpoint, así que a más redo pendiente (`actual_redo_blks`) más tiempo estimado de recuperación (`estimated_mttr`); el parámetro que lo acota es **`FAST_START_MTTR_TARGET`** —bajarlo fuerza checkpoints más frecuentes, deja menos redo pendiente y acorta el MTTR a costa de más escritura en datafiles—.

## Parte J — Archivos de control: qué guardan y cómo multiplexarlos

**Qué guarda** (`09-controlfiles-info.script.log`): el control file (~18 MB) es el mapa de la base. `v$controlfile` muestra **2 copias** (`control01.ctl`, `control02.ctl`, STATUS vacío = sana). `v$controlfile_record_section` expone sus secciones internas: `DATAFILE`, `TABLESPACE`, `REDO LOG`/`LOG HISTORY`, `ARCHIVED LOG`, `BACKUP SET` (metadatos de RMAN), etc. `control_file_record_keep_time` = **7** días. Y `ALTER DATABASE BACKUP CONTROLFILE TO TRACE` genera un **`CREATE CONTROLFILE` legible** (`controlfile_lab5.trc`, dentro del volumen) con todos los datafiles y redo logs — la última línea de defensa si se pierden todas las copias.

**Multiplexar** (`09-multiplexar-controlfile.sh`): añadí una **tercera copia** (`control03.ctl`). Procedimiento oficial con SPFILE: (1) `ALTER SYSTEM SET control_files … SCOPE=SPFILE` (CONTROL_FILES es **estático**, el cambio solo se aplica al arrancar), (2) `SHUTDOWN IMMEDIATE`, (3) `cp -p` de una copia sana al nuevo nombre (con la base parada todas son idénticas), (4) `STARTUP`. Idempotente. Al final Oracle mantiene las **tres** copias y la base queda healthy.

> **P14 · ¿Qué protege la multiplexación del control file en el mismo volumen y qué no? ¿Cómo se haría en producción?**
>
> La multiplexación son **varias copias idénticas que Oracle escribe a la vez**. **Protege de**: el borrado accidental o la corrupción de **un solo archivo** — si una copia se pierde, las otras dos son idénticas y siguen valiendo (lo comprobaré en el simulacro B). **No protege de**: perder el **disco o el volumen entero** (aquí las tres comparten volumen, así que se van juntas), ni de una corrupción **lógica** del contenido, que se copiaría a las tres. **En producción**: cada copia en un **disco y controladora distintos** (o grupos de ASM con redundancia), más `RMAN … CONFIGURE CONTROLFILE AUTOBACKAP ON` para tener copias del control file de momentos concretos — multiplexar ≠ hacer copias de seguridad.

> **J1 (tipo examen) · Una de las tres copias del control file se corrompe con la base abierta. ¿Qué ocurre?**
>
> **B. La instancia se detiene.** Aunque haya otras copias sanas, Oracle **no sigue "con las demás"**: si una copia del control file falla con la base abierta, la instancia se para. Hay que sustituir la copia dañada por una sana (o quitarla de `CONTROL_FILES`) y arrancar. No la recrea solo (C), no sigue sin aviso (A) y no hay por qué restaurar los datafiles (D).

> **J2 (tipo examen) · ¿Qué dos datos guarda el control file? (Elige dos.)**
>
> **A y C.** **A**: el nombre y la ubicación de los datafiles y redo logs (los vi en el `CREATE CONTROLFILE` trazado). **C**: el SCN del último checkpoint (lo medí en la Parte I: `v$datafile.checkpoint_change#`). **B** es falso (los parámetros viven en el SPFILE), **D** falso (las contraseñas, en el archivo de contraseñas) y **E** falso (las filas del diccionario están en los datafiles, no en el control file).

## Parte K — Registros de redo: grupos, miembros y cambios de log

**Grupos y miembros** (`10-redo.script.log`): mi base tenía **3 grupos** de **200 MB** (no los 20 MB de la imagen) con **1 miembro** cada uno. `10-redo.sql` añadió un **segundo miembro** a los tres (`redo01b/02b/03b.log`): LGWR escribe los miembros de un grupo **a la vez y de forma idéntica**. Recién añadidos aparecen `INVALID` —**no es un error**, es que aún no se ha escrito en ellos; tras dos `ALTER SYSTEM SWITCH LOGFILE` dejan de estar INVALID (menos `redo02b`, porque el grupo 2 no se ha vuelto a usar).

**Cambio de log**: el grupo `CURRENT` pasa al siguiente **en círculo** (2 → 3 → 1). Cada cambio dispara un checkpoint; el grupo viejo pasa a `ACTIVE` (aún necesario para recuperación) y luego a `INACTIVE`.

**Errores que Oracle rechaza** (sección 4): borrar el grupo `CURRENT` → **ORA-01623**; borrar un miembro del `CURRENT` → **ORA-01609**; y en mi caso borrar otro grupo → **ORA-00350** (`needs to be archived`) en vez del ORA-01567 del ejemplo, porque en **ARCHIVELOG** el grupo aún no archivado no se puede soltar: Oracle se protege y no deja perder redo.

> **P15 · Explica los estados CURRENT, ACTIVE e INACTIVE con tu evidencia 10 y por qué Oracle rechaza los tres borrados del paso 4.**
> - **CURRENT**: LGWR **está escribiendo** en él ahora (medido: el grupo 2 al inicio, luego el 3 y el 1). **No se puede reutilizar**.
> - **ACTIVE**: ya no es el actual, pero **sus cambios aún no están todos en los datafiles** (falta checkpoint) — medido: tras un switch el grupo viejo queda `ACTIVE` (grupo 2, 3, 1 a su vez). **No se puede reutilizar**: se necesitaría para recuperar la instancia.
> - **INACTIVE**: sus cambios **ya están en los datafiles**; reutilizable (y en ARCHIVELOG, además debe estar **archivado**).
> - **Por qué rechaza los borrados**: (4a) borrar el `CURRENT` (ORA-01623) = borrar el diario en uso; (4b) borrar un miembro del `CURRENT` (ORA-01609) perdería la redundancia del grupo activo; (4c) dejar menos de dos grupos usable (mi ORA-00350 / el ORA-01567) dejaría a LGWR sin dónde escribir el siguiente cambio. En los tres casos **Oracle se niega para no perder redo ni capacidad de escribir**.

> **K1 (tipo examen) · Un grupo de redo tiene estado ACTIVE. ¿Qué afirmación es correcta?**
>
> **C. Contiene cambios que aún podrían necesitarse para una recuperación de instancia.** Es la definición de `ACTIVE` (medido: el grupo viejo queda `ACTIVE` tras el switch hasta que el checkpoint lo vacía). **A** es falsa (escribir es `CURRENT`), **B** falsa (no se puede borrar sin más), **D** falsa (`ARCHIVED=YES` y `ACTIVE` no son lo mismo: un grupo puede estar activo sin archivar).

> **Reto profesional · Dimensiona el redo de TiendaSur (sin ejecutar la migración).**
>
> Conté los cambios de log por hora (`v$log_history`, `10-reto-dimensionar.script.log`): la hora más pesada que conservo es la **21**, con **9 cambios de log** (carga sostenida de los experimentos de índices y la cola de 600 000 filas). Con grupos de **200 MB**, eso son **9 × 200 MB = 1800 MB de redo en esa hora**. Para que esa carga produzca **como mucho 4 cambios/hora**: tamaño de grupo ≥ 1800 / 4 = **450 MB** → propongo **500 MB**. (La propia carga de TiendaSur, ~1,1 M de filas de la Parte B, a 200 MB ya fue solo un puñado de cambios; el pico de 9 es del bloque de experimentos.)
>
> **Comandos para migrar a 500 MB (escritos, NO ejecutados):**
> ```sql
> -- 1. Añadir grupos nuevos de 500 MB (sin parar la base)
> ALTER DATABASE ADD LOGFILE GROUP 4 '/opt/oracle/oradata/FREE/redo04.log' SIZE 500M;
> ALTER DATABASE ADD LOGFILE GROUP 5 '/opt/oracle/oradata/FREE/redo05.log' SIZE 500M;
> ALTER DATABASE ADD LOGFILE GROUP 6 '/opt/oracle/oradata/FREE/redo06.log' SIZE 500M;
> -- 2. Multiplexar los nuevos (segundo miembro en otro disco)
> ALTER DATABASE ADD LOGFILE MEMBER '/opt/oracle/oradata/FREE/redo04b.log' TO GROUP 4;
> ALTER DATABASE ADD LOGFILE MEMBER '/opt/oracle/oradata/FREE/redo05b.log' TO GROUP 5;
> ALTER DATABASE ADD LOGFILE MEMBER '/opt/oracle/oradata/FREE/redo06b.log' TO GROUP 6;
> -- 3. Forzar cambios de log y checkpoints hasta que los viejos queden INACTIVE
> ALTER SYSTEM SWITCH LOGFILE;  -- repetir hasta que 1, 2 y 3 estén INACTIVE
> ALTER SYSTEM CHECKPOINT;
> -- 4. Borrar los grupos viejos (ya INACTIVE y archivados)
> ALTER DATABASE DROP LOGFILE GROUP 1;
> ALTER DATABASE DROP LOGFILE GROUP 2;
> ALTER DATABASE DROP LOGFILE GROUP 3;
> ```
> **Trampa evitada**: no se puede redimensionar un grupo existente (hay que añadir grupos nuevos y borrar los viejos), y no se borra un grupo `ACTIVE` ni `CURRENT`.

## Parte L — ARCHIVELOG y Fast Recovery Area

**Activar la FRA y el modo** (`11-activar-archivelog.script.log`): mi base **ya estaba en ARCHIVELOG** (heredado del Lab 4), así que no hizo falta reiniciar. La FRA sí era nueva. El orden obligatorio: primero `db_recovery_file_dest_size` (4 GB) y después `db_recovery_file_dest` (dentro del volumen). El paso 2 lo comprueba a propósito: fijar la ruta **sin tamaño** da **ORA-02097 / ORA-19802** (`cannot use DB_RECOVERY_FILE_DEST without DB_RECOVERY_FILE_DEST_SIZE`). Verificación: `Archive Mode`, `Automatic archival Enabled`, destino `USE_DB_RECOVERY_FILE_DEST`, procesos **ARC0–ARC3** (en el Lab 4 no existían: solo aparecen con ARCHIVELOG) y `.arc` OMF (`o1_mf_…`) en `fra/FREE/archivelog/2026_10_26/`.

**Escenario de FRA llena** (`11-reto-fra-llena.script.log`): el script oficial con `SET estado = estado` (sin cambio real) no desbordó los 2 MB, así que lo provoqué de verdad con un **UPDATE real de 300 000 filas** (~100 MB de redo) y FRA a 2 MB. Cadena medida: **ORA-19815** (93,70 % → **100,00 %** usada, 0 restante) → **ORA-19809** (`limit exceeded for recovery files`) → **ORA-16038** (`log 2 sequence# 20 cannot be archived`) y **ORA-16014** (`no destinations available`) → el grupo queda **`ARC = NO`**. Remedios de más rápido a más correcto: (1) subir `db_recovery_file_dest_size` (lo hice → **ARCn reintenta solo** y los grupos 20 y 21 pasaron a archivarse, FRA a 328,9 MB); (2) RMAN `BACKUP ARCHIVELOG ALL DELETE INPUT` / `DELETE OBSOLETE`; (3) política de retención + alerta al 80 %. **Nunca `rm`**: Oracle no se entera y deja FRA y control file desincronizados.

> **P16 · Describe la cadena de causas del escenario de la FRA llena, desde ORA-19815 hasta que la base deja de aceptar cambios.**
>
> 1. La FRA alcanza su límite (`db_recovery_file_dest_size`); Oracle avisa **ORA-19815** — medido: 93,70 % y después **100,00 %** con 0 bytes restantes.
> 2. ARCn no puede escribir el redo archivado → **ORA-19809** (`limit exceeded for recovery files`).
> 3. El cambio de log no puede archivarse: **ORA-16038** (`log 2 sequence# 20 cannot be archived`) / **ORA-16014** (`no destinations available`); el grupo se queda **`ARC = NO`**.
> 4. En ARCHIVELOG, LGWR **no puede reutilizar** un grupo que no esté archivado, así que no puede seguir escribiendo.
> 5. Toda sesión que genere redo se queda **esperando** en `log file switch (archiving needed)` —**no da error, espera**—; las conexiones nuevas acaban recibiendo **ORA-00257**.
> 6. Resultado: **la base deja de aceptar cambios** que generan redo (DML/DDL). Remedios: subir el tamaño (ARCn reintenta **solo**, medido), o RMAN `DELETE INPUT`/`DELETE OBSOLETE`; nunca `rm`.

> **L1 (tipo examen) · `ALTER SYSTEM SET db_recovery_file_dest = '/u03/fra'` en una base sin FRA configurada da error. ¿Causa?**
>
> **B. Falta fijar antes `DB_RECOVERY_FILE_DEST_SIZE`.** Medido: **ORA-02097 / ORA-19802** — el tamaño es obligatorio y va **primero**. **A** es falsa (no hace falta ARCHIVELOG para tener FRA), **C** falsa (no es estático: lo fijé con `SCOPE=BOTH` sin reiniciar) y **D** falsa (no exige ASM).

> **L2 (tipo examen) · Sesiones esperando en «log file switch (archiving needed)» y conexiones nuevas con ORA-00257. ¿Qué dos acciones lo resuelven? (Elige dos.)**
>
> **A y C.** **A**: aumentar `DB_RECOVERY_FILE_DEST_SIZE` si hay disco — medido: al devolver a 4 GB, ARCn reintentó y archivó solo. **C**: copiar los archivados con RMAN y borrarlos con `DELETE INPUT` (libera espacio sin romper el control file). **B** es falsa (más `SWITCH LOGFILE` empeora), **D** falsa (NOARCHIVELOG en caliente no se puede y no arregla el archivado pendiente) y **E** falsa (`rm` deja la FRA y el control file desincronizados; hay que hacerlo con RMAN).

## Parte M — Undo: lectura consistente y su coste en redo

**Dos sesiones sobre la misma fila** (`12-lectura-consistente.script.log`): A hace `UPDATE` de la fila 101 a `EGRESADO` y tarda 25 s en confirmar. Mientras tanto, B:
1. **Ve `ACTIVO`** (el valor confirmado), reconstruido con el undo aunque el bloque ya dice `EGRESADO`.
2. La transacción de A consume undo: `v$transaction` = **1 bloque / 1 registro**.
3. A mantiene **TM modo 3** (`ACA_ESTUDIANTES`) y **TX modo 6** (la fila).
4. B intenta bloquear (`FOR UPDATE WAIT 3`) → **ORA-00054 + ORA-40097** (`transaction ID 1.20.674`).
5. Tras el COMMIT de A, B ve **`EGRESADO`**.
6. **Flashback Query** 40 s atrás → **`ACTIVO`** (leído del undo).
7. Reparación lógica con el propio undo (lab repetible). `undo_retention` = **900**, `undo_management AUTO`, `UNDOTBS1`.

**Undo y redo por DML** (`12-undo-y-redo.script.log`, 10 000 filas):
| Operación | Undo (bloques / KB) | Redo (KB) | …describe el undo (KB) | Redo del ROLLBACK (KB) |
|---|---|---|---|---|
| INSERT | 148 / 1184 | 4965 | 2050 | 444 |
| UPDATE (`canal`) | 71 / 568 | 1260 | 540 | 751 |
| **DELETE** | **431 / 3448** | **7184** | 3299 | **4732** |

> **P17 · Explica, con los pasos 1 a 4 de tu evidencia 12, la frase «lectores no bloquean a escritores».**
> - **Paso 1**: A ya escribió `EGRESADO` en el bloque (escritor), pero **B lee `ACTIVO`** sin esperar: el lector **no** se bloquea ni bloquea; reconstruye la versión confirmada con el undo.
> - **Pasos 2-3**: A solo tiene bloqueos TM 3 y TX 6 sobre su fila — no bloquea a los lectores, solo a otros **escritores**.
> - **Paso 4**: cuando B deja de ser lector y quiere **escribir** (`FOR UPDATE`), ahí sí choca con A: **ORA-00054**. Es el único conflicto real: **dos escritores sobre la misma fila**. Espejo: *escritores no bloquean a lectores* (paso 1). En Oracle el bloqueo TX vive en la cabecera del bloque (lista ITL), no en una tabla de bloqueos en memoria.

> **P18 · ¿Por qué un DELETE genera más undo que un INSERT? ¿Por qué el ROLLBACK también genera redo?**
> - **DELETE**: para deshaylo hay que guardar **la fila entera** (todas las columnas) **y sus entradas de índice**; medido **431 bloques / 3448 KB**. **INSERT** solo necesita «borra este ROWID» → **148 bloques / 1184 KB** (≈ 1/3). UPDATE guarda solo las columnas cambiadas (`canal`, sin índice) → el menor (71).
> - **ROLLBACK genera redo** porque el undo vive en `UNDOTBS1`, que también está en el buffer cache y puede perderse en una caída: para poder deshacer **después** del crash, Oracle debe poder rehacer **primero** el undo, y eso se protege con redo; además deshacer es aplicar cambios inversos, que también generan redo. Medido: el ROLLBACK del DELETE generó **4732 KB** de redo (casi tanto como el propio DELETE). «Casi la mitad del redo describe el undo» (columna 4).

> **M1 (tipo examen) · A hace un `UPDATE` sin confirmar. ¿Qué ve B al consultar la fila?**
> **C. El valor confirmado anterior, reconstruido con el undo.** Medido: B ve `ACTIVO` (paso 1). No es el nuevo (A), no hay error (B no escribe) y no espera (los lectores no se bloquean).

> **M2 (tipo examen) · ¿Qué operación de 10 000 filas genera, en general, MÁS undo?**
> **C. DELETE.** Medido: **431 bloques / 3448 KB** (≈ 3× el INSERT). Guarda la fila entera y sus índices.

> **M3 (tipo examen) · Informe nocturno con ORA-01555. ¿Qué dos medidas son adecuadas? (Elige dos.)**
> **B y D.** **B**: subir `UNDO_RETENTION` y el tamaño del tablespace de undo (o AUTOEXTEND). **D**: `ALTER TABLESPACE undotbs1 RETENTION GUARANTEE` si la consulta es crítica (garantiza la retención a riesgo de que las transacciones fallen). `v$undostat` lo mide (`MAXQUERYLEN`, `SSOLDERRCNT`). **A** (redo logs) y **E** (`LOG_BUFFER`) no tienen relación con undo; **C** (NOARCHIVELOG) tampoco arregla el undo.

> **Reto profesional · El coste de un DELETE en tu FRA.**
>
> Anoté `v$recovery_file_dest.space_used` = **346,9 MB**, ejecuté `12-undo-y-redo.sql` otra vez y forcé `ALTER SYSTEM ARCHIVE LOG CURRENT` (`12-reto-fra-delete.script.log`). La FRA pasó a **493,2 MB**: **creció 146,3 MB** (un solo `.arc`).
> El redo que generó el script (delta de `v$sysstat 'redo size'`) fue **17,4 MB** (452426 → 470236 KB): DML 11,6 MB + rollbacks 5,7 MB. **La FRA creció mucho más (146,3 MB) que el redo del script (17,4 MB)** porque el archivo archivado no es «lo que hizo el script» sino **todo el redo acumulado en el grupo actual desde el último archivado** —actividad interna, el trabajo previo de las Partes L y M— en cuanto forcé el cambio de log. Un `.arc` = el contenido de un grupo completo, no una transacción.

## Parte N — LGWR, DBWn y write-ahead logging

**La regla del registro previo a la escritura** (`13-lgwr-dbwn.script.log`), midiendo `v$sysstat` y `v$bh` desde `CDB$ROOT`:
| Paso | Redo (KB) | Escrituras LGWR | Commits | Bloques DBWn | Bloques sucios (tabla) |
|---|---|---|---|---|---|
| 0. Punto de partida | — | — | — | — | 0 |
| 1. UPDATE 20 000 filas + COMMIT | **+8161** | **+7** | +1 | **0** | **231** |
| 2. `ALTER SYSTEM CHECKPOINT` | +14 | +1 | 0 | **+614** | **0** |

El COMMIT movió **redo con LGWR** y dejó los **231 bloques sucios en memoria** (DBWn no escribió nada); el CHECKPOINT fue lo que **DBWn** usó para volcar **614 bloques** (los 231 de la tabla + undo + otros de la instancia) a los datafiles. Es más rápido escribir ~8 MB secuenciales en el redo que cientos de bloques dispersos.

> **P19 · Con tu evidencia 13: ¿dónde está la garantía de durabilidad justo después del COMMIT? ¿Y después del checkpoint?**
> - **Justo después del COMMIT**: en el **redo del online redo log escrito por LGWR**. Medido: paso 1 con **+8161 KB** de redo y **+7 escrituras de LGWR**, pero **0 bloques de DBWn** y la tabla aún con **231 bloques sucios**. Los datos NO están en los datafiles; la garantía es que el cambio quedó **descrito en el redo en disco**, de modo que si cae la instancia se rehace («log file sync»).
> - **Después del CHECKPOINT**: en los **datafiles**, hasta el SCN del checkpoint. Medido: paso 2 con **+614 bloques escritos por DBWn** y sucios a **0**. Ahora los bloques ya están físicamente en disco y el control file apunta ese SCN; la recuperación solo necesita rehacer el redo generado **después** de ese checkpoint.

> **N1 (tipo examen) · Una sesión recibe «Commit complete». ¿Qué está garantizado en ese momento?**
> **A. El redo de la transacción está escrito en el redo log online.** Medido: COMMIT → LGWR +7, redo +8161 KB, **DBWn = 0**. No implica datafiles (B), ni archivado en la FRA (C), ni checkpoint (D).

> **N2 (tipo examen) · ¿En qué dos situaciones escribe DBWn bloques sucios en los datafiles? (Elige dos.)**
> **B y C.** **B**: en un **checkpoint** (medido: paso 2, DBWn +614). **C**: cuando un proceso servidor **no encuentra buffers libres**. **A** es falsa (el COMMIT escribe redo con LGWR, no datafiles), **D** falsa (cada 3 s escribe **LGWR**, no DBWn) y **E** falsa (LGWR terminar el log buffer no dispara a DBWn). **Nunca «por un COMMIT»**.

## Parte O — Simulacros de fallo (game day)

Cuatro fallos reales, de menos a más grave. Medí **RTO y RPO** en cada uno.

**A · Caída de instancia** (`14a-caida-instancia.script.log`): `SHUTDOWN ABORT` tras dejar 102 `EGRESADO` (confirmado) e 103 `INACTIVO` (sin confirmar). Al `STARTUP`, SMON recuperó solo: alert log `Beginning crash recovery` → `Recovery starting at checkpoint rba (logseq 23 block 20553), scn 5375583` → `read 76 KB redo, 84 data blocks need recovery` → `Completed crash recovery` → `opened at log sequence 24`. Resultado: **102 = EGRESADO** (durabilidad), **103 = ACTIVO** (atomicidad). **RTO = arranque automático (segundos); RPO = 0.**

**B · Pérdida de una copia del control file** (`14b-perdida-controlfile.script.log`): con la base parada borré `control03.ctl`. El arranque se detuvo en **NOMOUNT** con **ORA-00205** (`STATUS STARTED`); el alert log dice `ORA-00202: control file: .../control03.ctl` + `ORA-27037`. Reparación = `cp -p control01.ctl control03.ctl` + `MOUNT` + `OPEN`. **RTO = minutos; RPO = 0.**

**C · Borrado de una tabla** (`14c-simulacro-restauracion.script.log`): `DROP` sin `PURGE` → papelera (`BIN$…`) → `FLASHBACK TABLE … TO BEFORE DROP` lo devuelve en segundos. `DROP … PURGE` → `ORA-00942` (sin papelera) → restauré la copia `lab5-pre-simulacro` (**1.5 G**). **RTO = 83 s; RPO = 2 s** (todo lo hecho entre copia y fallo).

**D · Pérdida de un datafile** (`14d-perdida-datafile.script.log`): copia RMAN de `TBS_ACADEMIA`, cambio confirmado **después** (104 → `EGRESADO`), `rm` del datafile 16 → **ORA-01116 / ORA-01110 / ORA-27041**. Oracle **cerró la PDB** (camino `ORA-63999`, PDB `MOUNTED`); `RESTORE DATAFILE 16` + `RECOVER DATAFILE 16` → `media recovery complete`; `ALTER PLUGGABLE DATABASE FREEPDB1 OPEN` → `READ WRITE`. **104 = EGRESADO** (el RECOVER aplicó el redo posterior a la copia). **RTO = 11 s; RPO = 0.**

> **P20 · Simulacro A: explica roll forward y roll back con las filas 102 y 103 y las líneas del alert log.**
> - **Roll forward (rehacer)**: SMON lee el redo desde el último checkpoint —`Recovery starting at checkpoint rba (logseq 23 block 20553), scn 5375583`— y rehace los bloques que no llegaron al disco —`read 76 KB redo, 84 data blocks need recovery`, `Started/Completed redo application`. El redo **rehace lo confirmado y lo no confirmado por igual** (no distingue): reconstruye 102 y 103 tal como estaban al cortar.
> - **Roll back (deshacer)**: con ese undo, SMON **deshace la transacción no confirmada** (103). Resultado medido: **102 = EGRESADO** (durabilidad: lo confirmado sobrevive) y **103 = ACTIVO** (atomicidad: lo no confirmado se borra). Nadie intervino: un `STARTUP` normal basta —`Completed crash recovery`, `opened at log sequence 24`.

> **P21 · Simulacros C y D: tu RTO y tu RPO en cada uno. ¿Por qué son tan distintos?**
> - **C** (restauración completa por una tabla): **RTO = 83 s**, **RPO = 2 s**.
> - **D** (restaurar un archivo con RMAN + redo): **RTO = 11 s**, **RPO = 0**.
> - **Por qué tan distintos**: C restaura **toda la base (1.5 G)** desde una copia en frío —el RTO crece con el **tamaño de la base**, no con el del daño (restauré 1.5 G por **una** tabla)— y su RPO es el tiempo desde la última copia (pierdes todo lo posterior). D restaura **un solo archivo** y el `RECOVER` **rehace el redo archivado y en línea** desde la copia hasta el fallo: RTO mínimo y **RPO = 0** porque ARCHIVELOG garantiza no perder ningún COMMIT. La lección: a mayor disponibilidad necesaria, más ARCHIVELOG y RMAN, menos «copias en frío».

> **O1 (tipo examen) · Tras un corte de luz, el DBA ejecuta `STARTUP`. ¿Qué ocurre?**
> **B. SMON aplica el redo online y deshace las transacciones no confirmadas; la base abre sin intervención.** Medido en el simulacro A. No hay que hacer `RECOVER DATABASE` manual (A), ni restaurar datafiles (C), y **no** se pierde nada confirmado (D).

> **O2 (tipo examen) · Tres copias del control file; una se borra con la base cerrada y `STARTUP` da ORA-00205. ¿Qué dos acciones abren la base sin perder datos? (Elige dos.)**
> **B y D.** **B**: copiar una copia sana sobre la perdida y montar (medido en el simulacro B). **D**: quitar la copia perdida de `CONTROL_FILES` en el SPFILE, reiniciar y montar. **A** es falsa (`RECOVER DATABASE USING BACKUP CONTROLFILE` es para cuando no queda ninguna copia y exige recuperación + `RESETLOGS`), **C** falsa (`RESETLOGS` puede perder datos y aquí no hace falta) y **E** falsa (los datafiles están sanos; restaurarlos es desproporcionado).

> **O3 (tipo examen) · En ARCHIVELOG se pierde el datafile de un tablespace de aplicación. ¿Secuencia que lo recupera sin cerrar la base y sin perder datos?**
> **B. `ALTER DATABASE DATAFILE n OFFLINE; RESTORE DATAFILE n; RECOVER DATAFILE n; ALTER DATABASE DATAFILE n ONLINE;`** Es el camino A del simulacro D. **A** cierra la base y usa `RESETLOGS`; **C** omite el `OFFLINE` y el `RECOVER`; **D** (`FLASHBACK DATABASE`) no sirve para un fallo de medios.

> **O4 (tipo examen) · `DROP TABLE ventas PURGE` hace 10 min; ARCHIVELOG + RMAN. ¿Qué recupera la tabla sin perder cambios de otras tablas?**
> **D. `RMAN RECOVER TABLE` hasta un instante anterior al DROP.** Recupera **solo esa tabla** a un punto en el tiempo con la copia de RMAN + redo archivado; el resto de tablas conservan sus cambios. **A** no sirve (`PURGE` la sacó de la papelera), **B** restauraría toda la base y **perdería** los cambios de otras tablas, **C** es solo una consulta (no recupera la tabla).

> **Reto profesional · El runbook del simulacro D.**
> Redactado en **`docs/runbooks/perdida-datafile.md`** (una página): los tres ORA- del síntoma (más el ORA-63999), comprobaciones previas (`ARCHIVELOG`, copia con `LIST BACKUP OF DATAFILE n`, estado de la PDB en `v$pdbs`), los **dos caminos** (PDB `READ WRITE` → `OFFLINE`/`RESTORE`/`RECOVER`/`ONLINE`; PDB `MOUNTED` → esperar, `RESTORE`/`RECOVER`, `ALTER PLUGGABLE DATABASE … OPEN`), la verificación (`v$pdbs` = `READ WRITE` + fila de control) y a quién avisar (escalada si es SYSTEM/undo de la raíz o si no hay ARCHIVELOG/copia).

> **Retrospectiva SRE (RTO/RPO de los cuatro, sorpresa y mejora).**
> | Simulacro | RTO | RPO | Sorpresa | Qué cambiaría |
> |---|---|---|---|---|
> | A · caída | automático (s) | 0 | Solo hizo falta **76 KB de redo / 84 bloques**: la caída cayó justo tras un checkpoint | Nada: es automático; usar `SHUTDOWN IMMEDIATE` para copias en frío |
> | B · control file | minutos | 0 | Se para en **MOUNT** y la reparación es un `cp` | Mis 3 copias están en el **mismo volumen**: un desastre real se las lleva a las tres → repartir discos |
> | C · tabla borrada | **83 s** | 2 s | El RTO crece con el **tamaño de la base** (1.5 G por **una** tabla) | Para una tabla usar `RMAN RECOVER TABLE`, no restauración completa |
> | D · datafile | **11 s** | 0 | Oracle **cerró la PDB entera** (ORA-63999) antes de que yo pudiera ponerlo `OFFLINE` | Vigilar ORA-63999; el runbook ya cubre los dos caminos |

## Parte P — Runbook de salud y verificación final

**`15-healthcheck.sql`** (con `C##OPS_RO`, solo lectura; `15-healthcheck.spool.log`): 9 secciones que un SRE revisa cada mañana en un minuto. Medido hoy: **disponibilidad** OPEN / READ WRITE · ARCHIVELOG / FREEPDB1 READ WRITE; **espacio** sin tablespaces >80 %; **recuperabilidad** FRA **546/4096 MB (13,3 %)**, último archivado 22:18, **3** copias de control file, **0** grupos con un solo miembro; **capacidad** processes 101/200, sessions 131/322; **cambios de log** 21h = **15**; **RMAN** 1 copia COMPLETED (38 MB); **índices** solo «sin estadísticas» en esquemas vacíos; **undo** 0 ORA-01555.

**`16-verificacion-final.sh`** (`16-verificacion-final.script.log`): **RESULTADO: TODO OK**. Comprueba backup íntegro, TiendaSur 100000/1000000, los 5 índices exactos de PEDIDO tras V005, DNI único, FRA 4 G en SPFILE, filas 101/102/104 de vuelta a ACTIVO, 60000 matrículas, copias RMAN y las 16 evidencias.

> **P22 · Clasifica cada error ORA- del bloque 5 de tu runbook: incidente real, efecto del laboratorio o ruido conocido. ¿Qué Parte lo explica?**
>
> De mi bloque 5 (`15-healthcheck.spool.log`), **ninguno es un incidente real**:
> - **ORA-63999** (`data file suffered media failure`), **ORA-01113** (`file 26 needs media recovery`) y **ORA-01110** (`data file 16: .../academia01.dbf`): **efecto del laboratorio — Parte O, simulacro D**. Son la huella de la pérdida de datafile que provoqué: al reabrir la PDB, Oracle revisó las cabeceras y marcó los archivos no al día; se recuperaron y la verificación final da TODO OK.
> - **ORA-00202** (`control file: control03.ctl`) y **ORA-205** (`signalled during ALTER DATABASE MOUNT`): **efecto del laboratorio — Parte O, simulacro B** (borré `control03.ctl` a propósito).
> - **ORA-00800** (`soft external error … Set Priority Failed`, LGWR/VKTM): **ruido conocido del entorno** (ya clasificado en el **Lab 4**: Docker no puede fijar prioridad de proceso; inofensivo).
>
> **Lección**: el bloque 5 no se «limpia», se **clasifica**. Cada ORA se anota como incidente real / efecto del laboratorio / ruido, y solo un incidente real escala.

> **Reto profesional · Un umbral que dispare una alerta (sección 3 · FRA).**
>
> La consulta que devuelve **una sola fila solo cuando hay que despertar a alguien** (vacío = bien):
> ```sql
> -- FRA por encima del 85 %: actúa de día (Parte L); al 100 % la base deja de archivar y se detiene
> SELECT 'FRA CRITICA: ' || ROUND(100 * space_used / NULLIF(space_limit, 0), 1) || '% (' ||
>        ROUND(space_used / 1048576) || ' de ' || ROUND(space_limit / 1048576) || ' MB)'
> FROM v$recovery_file_dest
> WHERE 100 * space_used / NULLIF(space_limit, 0) > 85;
> ```
> (Variante para la sección 7: `SELECT 'SIN COPIA RMAN en 24 h' FROM dual WHERE NOT EXISTS (SELECT 1 FROM v$rman_backup_job_details WHERE status='COMPLETED' AND start_time > SYSTIMESTAMP - INTERVAL '1' DAY);`). Es la conexión entre estas comprobaciones y un sistema de alertas: convierte un incidente nocturno en un aviso diurno.

> **Del punto de control: los 15 cambios de log de la hora 21 y el bloque 7 vacío.**
> - **15 cambios/hora** con grupos de **200 MB** = ~3 GB de redo en la hora punta: los provocaron **los experimentos de las Partes B–H** (índices, cola de 600k filas). En **producción**, decenas de cambios/hora indicarían **redo dimensionado a la baja** o una **carga masiva** a investigar (Parte K); no es preocupante aquí porque es el pico deliberado del laboratorio, no una carga continua.
> - **Si el bloque 7 (RMAN) saliera vacío en producción**: **actuaría hoy mismo**. Sin copia de RMAN la base **no se puede recuperar de un fallo de medios** (simulacro D sería imposible): configuraría de inmediato un backup RMAN (`BACKUP DATABASE` + `CONFIGURE CONTROLFILE AUTOBACKUP ON`) y su retención. **Vacío no es un dato, es una alarma.**
