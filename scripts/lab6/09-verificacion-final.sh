#!/usr/bin/env bash
# scripts/lab6/09-verificacion-final.sh — comprobación automática del estado final del Lab 6
set -uo pipefail
source scripts/deployment/env/00-config.sh
source scripts/ops/cabecera.sh "$(basename "$0" .sh)" || exit 2   # Lab 6: cabecera de evidencia (alumno, hora, contenedor, SCN)
fallos=0
ok()    { printf '  [OK]    %s\n' "$1"; }
fallo() { printf '  [FALLO] %s  -> repasa %s\n' "$1" "$2"; fallos=$((fallos + 1)); }
comprobar() { if [ "$2" = "$3" ]; then ok "$1 ($2)"; else fallo "$1: hay '$2', se esperaba '$3'" "$4"; fi; }
VALORES=$(docker exec -i -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 "$CONT_NAME" sqlplus -s -L / as sysdba <<'SQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 300
SELECT 'cdb=' || open_mode || '/' || log_mode FROM v$database;
SELECT 'controlfiles=' || COUNT(*) FROM v$controlfile;
SELECT 'pdb=' || open_mode || '/' || restricted FROM v$pdbs WHERE name = 'FREEPDB1';
SELECT 'estado_guardado=' || NVL(MAX(state), 'ninguno') FROM dba_pdb_saved_states WHERE con_name = 'FREEPDB1';
SELECT 'dbfiles_en_spfile=' || isspecified FROM v$spparameter WHERE name = 'db_files';
SELECT 'servicio=' || COUNT(*) FROM v$active_services WHERE name = 'academia_app';
SELECT 'bloqueados=' || COUNT(*) FROM v$session WHERE blocking_session IS NOT NULL;
ALTER SESSION SET CONTAINER = FREEPDB1;
SELECT 'servicio_def=' || COUNT(*) FROM dba_services WHERE name = 'academia_app';
SELECT 'app=' || account_status || '/' || common FROM dba_users WHERE username = 'APP_ACADEMIA';
SELECT 'app_rol=' || COUNT(*) FROM dba_role_privs WHERE grantee = 'APP_ACADEMIA' AND granted_role = 'ROL_APP_ACADEMIA';
SELECT 'app_directos=' || COUNT(*) FROM dba_tab_privs WHERE grantee = 'APP_ACADEMIA';
SELECT 'app_resumable=' || COUNT(*) FROM dba_sys_privs WHERE grantee = 'APP_ACADEMIA' AND privilege = 'RESUMABLE';
SELECT 'ana=' || account_status || '/' || profile FROM dba_users WHERE username = 'ANA_GARCIA';
SELECT 'ana_rol=' || COUNT(*) FROM dba_role_privs WHERE grantee = 'ANA_GARCIA' AND granted_role = 'ROL_SECRETARIA_ACADEMIA';
SELECT 'perfil=' || limit FROM dba_profiles WHERE profile = 'PRF_PERSONAS' AND resource_name = 'FAILED_LOGIN_ATTEMPTS';
SELECT 'esquema_priv=' || COUNT(*) FROM dba_schema_privs WHERE grantee = 'ROL_LECTURA_ACADEMIA' AND schema = 'ADMIN_ACADEMIA';
SELECT 'col_priv=' || COUNT(*) FROM dba_col_privs WHERE grantee = 'ROL_SECRETARIA_ACADEMIA' AND column_name = 'ESTADO';
SELECT 'efimeros=' || COUNT(*) FROM dba_users WHERE username IN ('U6_A', 'U6_B', 'PRUEBA_DEBIL');
SELECT 'tbs_hist=' || ROUND(MAX(maxbytes) / 1048576) FROM dba_data_files WHERE tablespace_name = 'TBS_ACADEMIA_HIST';
SELECT 'registro=' || COUNT(*) FROM carga_hist.registro;
SELECT 'cuota=' || ROUND(max_bytes / 1048576) FROM dba_ts_quotas WHERE username = 'CARGA_HIST' AND tablespace_name = 'TBS_ACADEMIA_HIST';
SELECT 'restos_lab6=' || COUNT(*) FROM dba_objects WHERE owner = 'ADMIN_ACADEMIA' AND object_name LIKE '%LAB6%';
SELECT 'papelera=' || COUNT(*) FROM dba_recyclebin WHERE owner = 'ADMIN_ACADEMIA';
SELECT 'invalidos=' || COUNT(*) FROM dba_objects WHERE status = 'INVALID'
   AND owner IN ('ADMIN_ACADEMIA', 'ADMIN_CLINICA', 'ADMIN_RETAIL', 'ADMIN_LOGISTICA', 'ADMIN_FINTECH', 'TIENDASUR', 'CARGA_HIST');
SELECT 'fila101=' || estado FROM admin_academia.aca_estudiantes WHERE estudiante_id = 101;
EXIT
SQL
)
val() { echo "$VALORES" | sed -n "s/^$1=//p" | awk 'NR==1' | tr -d '[:space:]'; }
echo "== Parte A · Punto de partida =="
BK=$(ls -d backups/*_lab6-inicio 2>/dev/null | tail -1)
if [ -n "$BK" ] && (cd "$BK" && sha256sum -c --quiet SHA256SUMS); then ok "copia $BK íntegra"; else fallo "no hay copia lab6-inicio íntegra" "Parte A"; fi
comprobar "CDB abierta y en ARCHIVELOG (herencia del Lab 5)" "$(val cdb)" "READWRITE/ARCHIVELOG" "Lab 5, Parte L"
comprobar "control files multiplexados (herencia del Lab 5)" "$(val controlfiles)" 3 "Lab 5, Parte J"
echo "== Partes B y C · Lista de turno, parámetros y estados =="
for f in scripts/ops/turno.sql scripts/ops/validar-arranque.sql scripts/ops/app.sh; do
  if [ -f "$f" ]; then ok "existe $f"; else fallo "falta $f" "Partes B a D"; fi
done
comprobar "FREEPDB1 abierta y sin RESTRICTED" "$(val pdb)" "READWRITE/NO" "Parte C"
comprobar "FREEPDB1 con estado guardado" "$(val estado_guardado)" "OPEN" "Parte C (SAVE STATE)"
comprobar "db_files sin valor propio en el SPFILE (RESET hecho)" "$(val dbfiles_en_spfile)" "FALSE" "Parte C (vuelta atrás)"
if ls "$EVID_LAB6"/config/*_02-init_desde_memoria.ora > /dev/null 2>&1; then ok "copia de texto de los parámetros en la evidencia"; else fallo "falta la copia del PFILE" "Parte C"; fi
echo "== Parte D · Servicios y sesiones =="
comprobar "servicio academia_app definido" "$(val servicio_def)" 1 "Parte D"
comprobar "servicio academia_app arrancado" "$(val servicio)" 1 "Parte D (o el incidente 2)"
comprobar "cuenta de aplicación local y abierta" "$(val app)" "OPEN/NO" "Parte D (o el incidente 3)"
echo "== Parte F · Almacenamiento =="
comprobar "TBS_ACADEMIA_HIST con techo de 40 MB" "$(val tbs_hist)" 40 "Parte F"
comprobar "histórico compactado (filas que quedan)" "$(val registro)" 2000 "Parte F (05-hwm-shrink)"
comprobar "cuota de CARGA_HIST" "$(val cuota)" 30 "Parte F (resumable)"
echo "== Parte G · Gobierno del acceso =="
comprobar "perfil PRF_PERSONAS (intentos fallidos)" "$(val perfil)" 3 "Parte G"
comprobar "ANA_GARCIA abierta con su perfil" "$(val ana)" "OPEN/PRF_PERSONAS" "Parte G"
comprobar "ANA_GARCIA con el rol de secretaría" "$(val ana_rol)" 1 "Parte G"
comprobar "privilegio de esquema del rol de lectura" "$(val esquema_priv)" 1 "Parte G"
comprobar "UPDATE solo de la columna ESTADO" "$(val col_priv)" 1 "Parte G"
comprobar "APP_ACADEMIA con su rol" "$(val app_rol)" 1 "Parte G"
comprobar "APP_ACADEMIA sin privilegios de objeto sueltos (deuda pagada)" "$(val app_directos)" 0 "Parte G"
comprobar "APP_ACADEMIA sin RESUMABLE (permiso temporal retirado)" "$(val app_resumable)" 0 "Parte G"
comprobar "usuarios efímeros borrados" "$(val efimeros)" 0 "Parte G (06-cascada)"
echo "== Partes H e I · Objetos, diagnóstico y guardia =="
comprobar "sin restos de los objetos de prueba" "$(val restos_lab6)" 0 "Parte H (07-objetos)"
comprobar "papelera de ADMIN_ACADEMIA vacía" "$(val papelera)" 0 "Parte H"
comprobar "objetos inválidos en esquemas de negocio" "$(val invalidos)" 0 "Parte H"
comprobar "sesiones bloqueadas ahora" "$(val bloqueados)" 0 "Parte I (incidente 1)"
comprobar "fila 101 en ACTIVO" "$(val fila101)" "ACTIVO" "Parte I (incidente 1)"
echo "== Evidencias =="
for n in 00 01 02 03 04 05 06 07 08; do
  if ls "$EVID_LAB6"/*/*_"$n"[a-z-]* > /dev/null 2>&1; then ok "evidencia $n"; else fallo "falta la evidencia $n" "la parte correspondiente"; fi
done
if [ -f docs/bitacora/lab6-respuestas.md ]; then ok "respuestas en docs/bitacora/lab6-respuestas.md"; else fallo "faltan las respuestas" "Parte J"; fi
if git ls-files --error-unmatch config/.env > /dev/null 2>&1; then fallo "config/.env está en Git" ".gitignore"; else ok "config/.env fuera de Git"; fi
if git ls-files | grep -E '^backups/|\.(ora|dbf|ctl|arc|bkp)$' | grep -vE '^docs/bitacora/(lab[0-9]+/)?evidencia/config/' > /dev/null; then fallo "hay archivos de la base en Git" ".gitignore"; else ok "ningún archivo de la base en Git"; fi
echo "== Uso de IA y autoría (las mismas reglas que aplica el docente) =="
ESTUDIANTE=$(set -a; . config/.env > /dev/null 2>&1; printf '%s' "${ESTUDIANTE:-}")
if [ -f login.sql ] && grep -q "DEFINE ESTUDIANTE = $ESTUDIANTE\$" login.sql; then ok "login.sql con tu código (prompt de SQLcl)"
else fallo "falta login.sql o no lleva tu código" "Parte A.3 (bash scripts/ops/alumno.sh)"; fi
if command -v python3 > /dev/null; then
  python3 scripts/ops/autoria.py --repo . --alumno "$ESTUDIANTE" --desde lab5-final
  fallos=$((fallos + $?))
else fallo "falta python3 para comprobar docs/bitacora/lab6-ia.md y las cabeceras" "sudo apt install -y python3"; fi
echo
if [ "$fallos" -eq 0 ]; then echo "RESULTADO: TODO OK. Lab 6 listo para entregar."; else echo "RESULTADO: $fallos FALLO(S). Corrige antes de abrir el PR."; fi
exit "$fallos"
