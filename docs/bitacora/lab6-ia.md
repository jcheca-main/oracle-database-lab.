He leído la política de uso de IA de la asignatura.

# Declaración de uso de IA · Lab 6 · E017

<!--
CÓMO SE RELLENA (léelo y borra este comentario si quieres; el script de evaluación lo ignora)
- La PRIMERA línea es obligatoria y no se toca: «He leído la política de uso de IA de la asignatura.»
- Copia este archivo como docs/bitacora/lab6-ia.md (junto a lab6-respuestas.md) y pon tu código en el título.
  Cada laboratorio tiene el suyo: en el Lab 7 será docs/bitacora/lab7-ia.md.
- Si NO has usado IA: deja solo la línea «No he usado IA.» y borra la entrada de ejemplo.
- Si la has usado: borra la línea «No he usado IA.» y escribe UNA entrada por cada uso, con los 7 campos.
  Un campo vacío es una entrada incompleta (D3: −0,5 por entrada).
- Preguntar a la IA como tutor o corregir la ortografía de un texto propio está permitido: decláralo también.
  Si no copiaste código, escribe «no aplica» en «Código recibido» y en «Evidencia de ejecución» (no cuentan como vacíos).
  Los demás campos son siempre obligatorios.
- Una entrada con TODOS los campos vacíos (la de ejemplo sin tocar) no cuenta: se ignora.
- El código copiado de una IA puntúa si lo EJECUTAS en tu contenedor, lo EXPLICAS con tus palabras,
  dices para qué lo usaste y adjuntas aquí el código y el prompt LITERAL.
-->

 He utilizado la IA como ayuda para que me valla guiando a la hora de realizar la practica, que me 
recomendara partes de codigo o si tenia algun tipo de problema con algun script en especifico. Para
asi poder realizar la practica. 

## Entrada 1 -> INC-601
- **Herramienta:** ChatGPT 
- **Prompt (literal, copiado tal cual):**
```text
	para la INC-601 que codigo me recomiendas poner?
```
- **Código recibido (el fragmento, o la ruta del archivo donde está):**
```sql
	ALTER SYSTEM KILL SESSION '55,44522' IMMEDIATE;
```
- **Dónde lo usé (parte, script o pregunta):** para la parte de las incidencias 
- **Propósito (para qué lo necesitaba):** ayuda
- **Qué hace (con mis palabras; línea a línea si es SQL corto):** elimina una session especifica 
- **Evidencia de ejecución (archivo de docs/bitacora/lab6/evidencia con mi cabecera):**  docs/bitacora/lab6/evidencia/script/20261124T182211Z_08-inc601-accion.script.log

## Entrada 2 -> INC-602
- **Herramienta:** ChatGPT
- **Prompt (literal, copiado tal cual):**
```text
        para la INC-602 que codigo es entonces si no es ni uno ni otro?
```
- **Código recibido (el fragmento, o la ruta del archivo donde está):**
```sql
        SELECT estudiante_id, estado FROM admin_academia.aca_estudiantes WHERE estudiante_id = 101;
```
- **Dónde lo usé (parte, script o pregunta):** para la parte de las incidencias
- **Propósito (para qué lo necesitaba):** ayuda
- **Qué hace (con mis palabras; línea a línea si es SQL corto):** hace una consulta sobre un estudiante en especifico
- **Evidencia de ejecución (archivo de docs/bitacora/lab6/evidencia con mi cabecera):**  docs/bitacora/lab6/evidencia/script/20261124T182408Z_08-inc601-validar.script.log

## Entrada 3 -> INC-603
- **Herramienta:** ChatGPT
- **Prompt (literal, copiado tal cual):**
```text
        y la INC-603 que dos instrucciones le hago entonces?
```
- **Código recibido (el fragmento, o la ruta del archivo donde está):**
```sql
        ALTER SESSION SET CONTAINER = FREEPDB1;
        ALTER USER app_academia ACCOUNT UNLOCK;
```
- **Dónde lo usé (parte, script o pregunta):** para la parte de las incidencias
- **Propósito (para qué lo necesitaba):** ayuda
- **Qué hace (con mis palabras; línea a línea si es SQL corto):** Desbloquea a un usuario de una sesion.
- **Evidencia de ejecución (archivo de docs/bitacora/lab6/evidencia con mi cabecera):**  docs/bitacora/lab6/evidencia/script/20261124T183218Z_08-inc603-desbloqueo.script.log








