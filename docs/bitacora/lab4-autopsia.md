# Autopsia de la instancia · Lab 4 (Parte N, reto)

Informe de la base **FREE** (Oracle 26ai Free, contenedor `oralab-26ai`) tras las correcciones del Lab 4.
Obtenido con `scripts/lab4/15-autopsia-instancia.sql`, ejecutado en **solo lectura** como `C##OPS_RO`
(`bash scripts/ops/ro.sh scripts/lab4/15-autopsia-instancia.sql`). Evidencia completa:
`docs/bitacora/lab4/evidencia/spool/20261024T132758Z_15-autopsia-instancia.spool.log`.

Mi base **no es la del guion del laboratorio**: está en ARCHIVELOG, tiene force logging y `common_user_prefix`
en su valor por defecto. Los hallazgos de abajo son los míos, con mis valores.

## Identidad (secciones 1-3)

| Dato | Valor |
|---|---|
| Instancia / host | FREE / `f49e437017b9` |
| Versión | 23.26.3.0.0 |
| Arranque | 2026-10-24 11:21 (OPEN, ACTIVE) |
| CDB / modo | `FREE`, **ARCHIVELOG**, READ WRITE, **FORCE_LOGGING YES**, FLASHBACK NO, PRIMARY |
| Contenedores | CDB$ROOT (RW), PDB$SEED (RO, 810 MB), FREEPDB1 (RW, 1462 MB) |
| SGA / PGA | SGA máx 1529 MB (buffer cache 1072, shared pool 416); PGA objetivo 512 MB, asignada 373 MB |
| Procesos | 85 de segundo plano (ARC0 ARC1 CKPT DBRM DBW0 LGWR LREG MMNL MMON PMON PSP0 RECO SMON VKTM) + 5 servidores |

## Hallazgos

| # | Sección | Hallazgo (evidencia) | Riesgo | Acción | Prioridad |
|---|---|---|---|---|---|
| 1 | 1 y 4 | ARCHIVELOG activo (ARC0-ARC3, 4 archived logs, 465 MB) pero **sin FRA**: `db_recovery_file_dest` vacío y `db_recovery_file_dest_size = 0`. Los archived logs van a disco sin límite ni retención gestionada. | Si el disco se llena de archived logs, la instancia se para porque LGWR no puede continuar. | Configurar FRA (`db_recovery_file_dest` + `size`) y política de retención de archived logs (Lab 5). | **Alta** |
| 2 | 4 | **Punto único de fallo en los archivos críticos**: 2 control files y los 3 miembros de redo viven todos en `/opt/oracle/oradata/FREE/`. | La pérdida de esa carpeta/volumen deja la base sin control ni redo: no arranca. | Multiplexar control files y un segundo miembro de redo por grupo en rutas distintas (Lab 5). | **Alta** |
| 3 | 4 y 9 | **ADR fuera del volumen persistente**: `diagnostic_dest = /opt/oracle`, y el alert log y los traces quedan en `/opt/oracle/diag/...`, que no persiste al recrear el contenedor. | Al recrear el contenedor se pierde la historia de diagnóstico (alert log, incidents). | `diagnostic_dest` en volumen persistente o logs centralizados fuera del contenedor. | **Media** |
| 4 | 6 | **Cuatro esquemas de negocio sin estadísticas**: `ADMIN_CLINICA`, `ADMIN_FINTECH`, `ADMIN_LOGISTICA`, `ADMIN_RETAIL` tienen `ALTURA_MAX` vacía. Solo `ADMIN_ACADEMIA` tiene estadísticas (altura 2). | El optimizador decide a ciegas en esos esquemas → planes subóptimos y consultas lentas. | `DBMS_STATS.GATHER_SCHEMA_STATS` en cada esquema. | **Media** |
| 5 | 6 | **2 índices de `ADMIN_ACADEMIA` con factor de agrupamiento cercano al número de filas** (`cf_cercano_a_filas = 2`). | Índices caros para rangos: cada salto del índice salta a bloques dispersos de la tabla. | Revisar en el Lab 5 (rebuild reordenando la tabla o el índice). | **Baja** |
| 6 | 9 | `common_user_prefix = C##` (su valor por defecto, por eso no aparece en el listado de parámetros cambiados). **A diferencia del guion, aquí NO está vacío**: los usuarios comunes respetan el prefijo. | Nulo. Es la imagen de prueba, pero conviene saberlo para no buscar usuarios "limpios". | Solo documentar. | **Ninguna** |
| 7 | 10 | **7 ORA- en 24 h, todos ruido**: `ORA-00800` ×4 ("soft external error" de `vktm`/`lgwr`, ruido del contenedor), `ORA-00031` (KILL SESSION de la Parte H), `ORA-65025` (DROP PDB de la Parte I) y `ORA-959` (DROP TABLESPACE de la Parte M). | Ninguno es un error real de la base; contarlos como incidentes inflaría las métricas. | Documentar y excluir de alertas; en producción mirar siempre el primer ORA- de cada bloque. | **Ninguna** |

## Lo que está sano

- **Ningún tablespace cerca del 85 %**: el más lleno es `TBS_ACADEMIA` al **2,3 %** (23 de 1024 MB); el resto de negocio por debajo del 1 %.
- **Ningún índice inválido** (`no_validos = 0` en los cinco esquemas).
- **Mínimo privilegio correcto**: ninguna cuenta de la casa tiene el rol DBA (solo las que mantiene Oracle), y `C##OPS_RO` no tiene privilegios `ANY` de escritura.
- **FORCE_LOGGING activo**: la base resiste la pérdida de datos tras un `RESETLOGS` (mejor que la imagen base del guion, que lo traía desactivado).
- **CDB y FREEPDB1 abiertas READ WRITE**; servicios `free`, `freeXDB` y `freepdb1` activos.

## Resumen para un jefe no técnico

La base está sana y arranca bien, con pocos datos (los tablespaces de negocio están casi vacíos) y sin índices rotos. Lo urgente es protegerla: los archivos de control y de redo están todos en un mismo sitio, y el archivado no tiene zona reservada, así que un fallo de disco o un llenado repentino podrían dejarla fuera de servicio. Además, cuatro de los cinco esquemas de negocio no tienen estadísticas, así que el motor de consulta decide sin información y puede tardar de más.
