#!/usr/bin/env bash
# scripts/lab4/16-verificacion-final.sh — comprobación automática del estado final del Lab 4
# Cada línea es OK o FALLO. Un FALLO dice qué parte del laboratorio repasar. Entrega solo con todo en OK.
set -uo pipefail
source scripts/deployment/env/00-config.sh
fallos=0
ok()    { printf '  [OK]    %s\n' "$1"; }
fallo() { printf '  [FALLO] %s  -> repasa %s\n' "$1" "$2"; fallos=$((fallos + 1)); }
comprobar() { if [ "$2" = "$3" ]; then ok "$1 ($2)"; else fallo "$1: hay '$2', se esperaba '$3'" "$4"; fi; }

# Una sola consulta como SYSDBA devuelve clave=valor; el resto del script solo compara
VALORES=$(docker exec -i "$CONT_NAME" sqlplus -s -L / as sysdba <<'SQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 200
SELECT 'open_mode=' || open_mode FROM v$database;
SELECT 'pdb=' || open_mode FROM v$pdbs WHERE name = 'FREEPDB1';
SELECT 'open_cursors=' || value FROM v$parameter WHERE name = 'open_cursors';
SELECT 'db_files_spfile=' || isspecified FROM v$spparameter WHERE name = 'db_files';
SELECT 'ops_ro=' || common FROM cdb_users WHERE username = 'C##OPS_RO' AND con_id = 1;
SELECT 'ops_ro_alert=' || COUNT(*) FROM dba_tab_privs WHERE grantee = 'C##OPS_RO' AND table_name = 'V_$DIAG_ALERT_EXT';
SELECT 'ops_ro_dml=' || COUNT(*) FROM dba_sys_privs WHERE grantee = 'C##OPS_RO' AND privilege LIKE '%ANY%' AND privilege NOT LIKE 'SELECT ANY DICTIONARY';
SELECT 'pdb_lab4=' || COUNT(*) FROM v$pdbs WHERE name = 'PDB_LAB4';
SELECT 'usuarios_prueba=' || COUNT(*) FROM cdb_users WHERE username LIKE '%LAB4%';
ALTER SESSION SET CONTAINER = FREEPDB1;
SELECT 'fuera_de_carpeta=' || COUNT(*) FROM dba_data_files
 WHERE tablespace_name LIKE 'TBS\_%' ESCAPE '\' AND file_name NOT LIKE '/opt/oracle/oradata/FREE/FREEPDB1/%';
SELECT 'tbs_lab4=' || COUNT(*) FROM dba_tablespaces WHERE tablespace_name = 'TBS_LAB4';
SELECT 'tbs_negocio=' || COUNT(*) FROM dba_tablespaces WHERE tablespace_name IN ('TBS_ACADEMIA', 'TBS_CLINICA', 'TBS_FINTECH', 'TBS_LOGISTICA', 'TBS_RETAIL');
SELECT 'con_password=' || COUNT(*) FROM dba_users WHERE username LIKE 'ADMIN\_%' ESCAPE '\' AND authentication_type <> 'NONE';
SELECT 'v002=' || (SELECT COUNT(*) FROM admin_academia.aca_estudiantes) || '/'
       || (SELECT COUNT(*) FROM admin_academia.aca_asignaturas) || '/'
       || (SELECT COUNT(*) FROM admin_academia.aca_matriculas) FROM dual;
EXIT
SQL
)
val() { echo "$VALORES" | sed -n "s/^$1=//p" | tr -d '[:space:]'; }

echo "== Parte A · Respaldo del Lab 3 =="
BK=$(ls -d backups/*_lab3-final 2>/dev/null | tail -1)
if [ -n "$BK" ] && (cd "$BK" && sha256sum -c --quiet SHA256SUMS); then ok "backup $BK íntegro"; else fallo "no hay backup lab3-final íntegro" "Parte A"; fi
echo "== Partes A, C y D · Correcciones del Lab 3 =="
comprobar "tablespaces de negocio" "$(val tbs_negocio)" 5 "Parte C"
comprobar "datafiles de negocio fuera de FREE/FREEPDB1" "$(val fuera_de_carpeta)" 0 "Parte C (03-reubicar)"
FUERA=$(docker exec "$CONT_NAME" bash -c 'for f in /opt/oracle/oradata/FREE/FREEPDB1/*.dbf; do r=$(readlink -f "$f"); case "$r" in /opt/oracle/oradata/*) ;; *) echo "$r";; esac; done' | wc -l)
comprobar "archivos cuya ruta real sale del volumen" "$FUERA" 0 "Parte A (diagnóstico)"
comprobar "cuentas ADMIN_* con contraseña" "$(val con_password)" 0 "Parte D (V003)"
comprobar "datos V002 estudiantes/asignaturas/matrículas" "$(val v002)" "20000/40/60000" "Parte D (V002)"
if docker port "$CONT_NAME" | grep '8181' > /dev/null; then fallo "el contenedor sigue publicando 8181" "Parte C (05 v2)"; else ok "8181 ya no se publica"; fi
echo "== Partes B, E y F · Cuenta de observabilidad, instancia y parámetros =="
comprobar "CDB abierta" "$(val open_mode)" "READWRITE" "Parte E"
comprobar "FREEPDB1 abierta" "$(val pdb)" "READWRITE" "Parte E (SAVE STATE)"
comprobar "C##OPS_RO es común" "$(val ops_ro)" "YES" "Parte B"
comprobar "open_cursors devuelto a su valor" "$(val open_cursors)" 300 "Parte F"
comprobar "db_files sin línea pendiente en el SPFILE" "$(val db_files_spfile)" "FALSE" "Parte F (RESET)"
echo "== Partes I a N · Contenedores, archivos, bloque, capacidad y filas migradas =="
comprobar "PDB de prueba PDB_LAB4 borrada" "$(val pdb_lab4)" 0 "Parte I (10-ciclo-vida-pdb)"
comprobar "usuarios de prueba *LAB4* borrados" "$(val usuarios_prueba)" 0 "Partes I y M (10-que-ve-cada-usuario, 14-filas-migradas)"
comprobar "C##OPS_RO lee el alert log (V_\$DIAG_ALERT_EXT)" "$(val ops_ro_alert)" 1 "Parte J (11-ampliar-ops-ro)"
comprobar "C##OPS_RO sin privilegios ANY de escritura" "$(val ops_ro_dml)" 0 "Parte B (mínimo privilegio)"
comprobar "banco de pruebas TBS_LAB4 borrado" "$(val tbs_lab4)" 0 "Parte M (14-filas-migradas, sección 8)"
if [ -n "$(ls docs/bitacora/lab4/evidencia/config/*_12-volcado-bloque.trc.txt 2>/dev/null)" ]; then ok "volcado de bloque guardado"; else fallo "falta el volcado del bloque" "Parte K (12-bloque.sh)"; fi
echo "== Evidencias =="
for n in 00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15; do
  if ls docs/bitacora/lab4/evidencia/*/*_"$n"-* >/dev/null 2>&1; then ok "evidencia $n"; else fallo "falta la evidencia $n" "la parte correspondiente"; fi
done
if [ -f docs/bitacora/lab4/evidencia/config/initFREE_lab4.ora ]; then ok "PFILE versionado"; else fallo "falta el PFILE" "Parte F"; fi
if git ls-files --error-unmatch config/.env >/dev/null 2>&1; then fallo "config/.env está en Git" ".gitignore"; else ok "config/.env fuera de Git"; fi
if git ls-files | grep '^backups/' > /dev/null; then fallo "hay backups versionados en Git" ".gitignore"; else ok "backups/ fuera de Git"; fi
echo
if [ "$fallos" -eq 0 ]; then echo "RESULTADO: TODO OK. Lab 4 listo para entregar."; else echo "RESULTADO: $fallos FALLO(S). Corrige antes de abrir el PR."; fi
exit "$fallos"
