#!/usr/bin/env bash
# scripts/deployment/env/13-verificacion-final.sh
source scripts/deployment/env/00-config.sh
set -a; source config/.env; set +a
echo "== 1. Docker =="
docker version --format 'Cliente {{.Client.Version}} / Motor {{.Server.Version}}'
echo "== 2. Imagen y digest =="
docker images --digests container-registry.oracle.com/database/free
echo "== 3. Contenedor =="
docker ps -a --filter "name=$CONT_NAME" --format '{{.Names}} {{.Status}} {{.Ports}}'
echo "== 4. Volumen persistente =="
docker volume ls --filter "name=$VOL_NAME"
echo "== 5. Base de datos lista (debe ser 1 o mas) =="
docker logs "$CONT_NAME" 2>&1 | grep -c "DATABASE IS READY TO USE"
echo "== 6. Entornos de negocio =="
docker exec -i "$CONT_NAME" sqlplus -s sys/"$ORACLE_PWD"@localhost:1521/"$SERVICE_PDB" as sysdba <<'SQL'
SET PAGESIZE 50
SELECT owner, COUNT(*) AS tablas FROM dba_tables
WHERE owner LIKE 'ADMIN\_%' ESCAPE '\' GROUP BY owner ORDER BY owner;
EXIT
SQL
echo "== 7. Java =="
java -version 2>&1 | head -n 1
echo "== 8. SQLcl =="
sql -version
echo "== 9. Secretos fuera de Git =="
git check-ignore -q config/.env && echo "OK: config/.env esta ignorado por Git" || echo "FALLO: config/.env NO esta ignorado"
