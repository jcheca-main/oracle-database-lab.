# Runbook — Pérdida de un datafile (media failure)

**Para quién:** compañero de guardia que no ha hecho el laboratorio.
**Qué es:** un datafile de un tablespace de negocio deja de poder leerse/escribirse (disco roto, borrado, NFS caído).
**Objetivo:** devolver el archivo al servicio con la base **abierta** y **sin perder ningún COMMIT**. En ARCHIVELOG esto es posible; sin ARCHIVELOG solo hay restauración completa en frío (se pierde lo posterior).

---

## 1. Síntoma

La aplicación recibe errores al leer/escribir objetos de ese tablespace. En el alert log verás (en este orden):

| Error | Qué te dice |
|---|---|
| `ORA-01116: error in opening database file N` | El número de archivo dañado. |
| `ORA-01110: data file N: '.../ruta/archivo.dbf'` | **Qué archivo** es exactamente. |
| `ORA-27041: unable to open file` + `Linux Error: 2: No such file or directory` | **La causa en el SO**: el archivo no existe / el disco no responde. |
| `ORA-639999: data file suffered media failure` *(opcional)* | **Oracle ya cerró la PDB entera** para protegerla. No es un error tuyo: es el aislamiento de fallos. |

## 2. Comprobaciones previas (2 minutos, antes de tocar nada)

```sql
-- a) ¿Estamos en ARCHIVELOG? (imprescindible para recuperar sin cerrar)
ARCHIVE LOG LIST;                      -- Database log mode: Archive Mode
-- b) ¿En qué estado está la PDB del archivo dañado?
SELECT name, open_mode FROM v$pdbs;    -- ¿READ WRITE o MOUNTED?
-- c) ¿Hay copia de RMAN del tablespace? (sustituye N por el nº del archivo)
--    En RMAN:
LIST BACKUP OF DATAFILE N;             -- debe mostrar un backupset reciente
```

Si **no** hay ARCHIVELOG → no sigas este runbook: avisa y escala (solo restauración completa en frío).
Si **no** hay copia de RMAN → se recupera con el datafile OFFLINE + la copia más cercana; escala a quien tenga el procedimiento de restores.

## 3. Camino A — la PDB sigue `READ WRITE` (solo ese tablespace caído)

```sql
-- Aísla el archivo dañado: el resto de la PDB sigue dando servicio
ALTER SESSION SET CONTAINER = <PDB>;
ALTER DATABASE DATAFILE N OFFLINE;
```
```text
# En RMAN (target /):
RESTORE DATAFILE N;
RECOVER  DATAFILE N;
```
```sql
-- Devuélvelo al servicio
ALTER DATABASE DATAFILE N ONLINE;
```

## 4. Camino B — Oracle ya cerró la PDB (`MOUNTED`, vino el ORA-63999)

**No** intentes `OFFLINE` mientras se cierra: fallará con `ORA-01089` y el RESTORE se pisa con el cierre. Espera a que `v$pdbs` diga `MOUNTED`:

```sql
-- Espera (desde la CDB$ROOT) hasta que esté completamente montada
SELECT name, open_mode FROM v$pdbs WHERE name = '<PDB>';   -- MOUNTED
```
```text
# En RMAN (target /), con la PDB montada:
RESTORE DATAFILE N;
RECOVER  DATAFILE N;
```
```sql
-- Reabre la PDB
ALTER PLUGGABLE DATABASE <PDB> OPEN;
```

## 5. Verificar que funcionó

```sql
SELECT name, open_mode FROM v$pdbs;                 -- debe decir READ WRITE
-- y una fila de control del tablespace dañado:
SELECT COUNT(*) FROM <esquema>.<tabla_de_control>;  -- responde sin ORA-
```

**No des el incidente por cerrado hasta que `v$pdbs` diga `READ WRITE`.**

## 6. A quién avisar

- **Siempre**: deja registro (qué archivo, cuándo, qué ORA, qué se hizo).
- **Escalada inmediata** si el archivo perdido es de **SYSTEM** o del **undo de la raíz** (ahí no basta con la PDB: hay que montar la CDB entera y recuperar con la base cerrada), o si no había copia/ARCHIVELOG.
- Aviso al dueño del servicio de la PDB afectada: si la PDB se cerró (ORA-63999), estuvo **toda** ella fuera durante el RTO, no solo el tablespace.

---

*Generado en el game day de la Parte O (Práctica 1 Lab 5). Camino medido en el entorno: ORA-63999 → PDB MOUNTED → RESTORE+RECOVER → OPEN; RTO 11 s, RPO 0.*
