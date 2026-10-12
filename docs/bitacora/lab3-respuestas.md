# Lab 3 - Respuestas de comprobación - Julio Checa (jcheca@alu.ucam.edu)
Issue #1, branch chore/1-install-oracle-environment

## Docker
1. Imagen es plantilla solo lectura (hello-world, alpine:3.20, database/free:latest). Contenedor es instancia viva de una imagen. En G2 `docker run hello-world` crea un contenedor que imprime y termina Exited 0. En G4 `docker run -it --name prueba alpine:3.20 sh` crea otro que sigue vivo hasta `exit` porque su proceso principal es sh.
2. En G5 el archivo estaba en el filesystem del contenedor (/tmp/nota.txt): al hacer `docker rm prueba` se borra todo. En G6 estaba en un named volume (/datos -> datos-prueba): el volumen sobrevive al `rm` del contenedor, el segundo contenedor lo vuelve a ver.
3. `docker ps` solo en marcha, `docker ps -a` todos incluidos detenidos. `Exited (0)` terminó bien, `Exited (1+)` terminó con error.
4. En `-p 8181:8181` el primero es mi equipo, el segundo el contenedor (anfitrión:contenedor). Con `-p 80:8080` en nginx no carga porque nginx escucha en 80 dentro, no en 8080.
5. Un contenedor vive lo que su proceso principal. hello-world termina tras imprimir. Oracle sigue Up porque su proceso es el motor de base de datos que no termina.
6. Digest sha256 es huella exacta bit a bit de la imagen. `:latest` cambia con el tiempo, el digest no. Lo registramos (f988b0... en mi evidencia 04, 13.8GB) para saber qué versión exacta instalé.
7. `docker volume rm oralab-26ai-data` borraría los datos. `docker rm oralab-26ai` solo borra el proceso, los datafiles siguen en el volumen.

## Git, organización y evidencia
8. Para que sea reproducible, verificable y reusable: scripts + evidencia + revisión en PR en vez de snowflake server solo en mi cabeza. Issue #1 -> branch -> commits por parte -> PR -> review -> merge.
9. `source` ejecuta en mi shell actual y deja variables (CONT_NAME, EVID, ts). `bash` lo ejecuta en hija que desaparece y se pierden. Por eso 00-config.sh siempre con source.
10. `20260915T091230Z_02-docker.script.log`: marca UTC ISO8601 compacta, `_02` paso Parte F, `docker` kebab-case descripción, `.script.log` salida de terminal (no spool SQL ni png captura).
11. `.gitattributes` fuerza `*.sh *.sql *.md text eol=lf`. Evita `$'\r': command not found` por CRLF de Windows y diffs con ruido en equipos mixtos.
12. Cada commit es una Parte con valor propio y evidencia. Con merge commit se conserva paso a paso. Squash lo aplastaría todo en uno y se perdería trazabilidad, que en Lab 2 sí queríamos simplificar.

## Seguridad
13. Capa1 `.gitignore` con `config/.env` y `backups/` antes de crearlos. Capa2 plantilla `config/.env.example` sin reales. Capa3 real `config/.env` local verificado con `check-ignore`. Capa4 leer con `set -a; source config/.env; set +a` sin teclear. Si saltas la 1, el `.env` entra en `git status` y acaba commiteado para siempre en historial.
14. Todo comando queda en `~/.bash_history` en plano. Con `-e ORACLE_PWD=MiClave` la clave queda ahí aunque el script no se suba. Con `"$ORACLE_PWD"` solo queda el nombre de variable.
15. No basta borrar en commit nuevo, sigue en historial recuperable con `git log -p`. Hay que rotar el secreto (cambiar contraseña, recrear contenedor), avisar al docente y limpiar branch. En empresa es incidente formal.

## Oracle y herramientas
16. `sqlplus` corre dentro del contenedor: `SPOOL` escribiría dentro del contenedor no en mi repo, y `@archivo.sql` buscaría dentro donde no existe (SP2-0310). Usamos redirección `< archivo.sql` desde mi equipo + `tee` para guardar spool fuera. Con SQLcl en mi equipo sí usamos SPOOL normal (evidencia 10).
17. `WHENEVER SQLERROR EXIT SQL.SQLCODE` detiene el script al primer fallo con código error. Sin ella seguiría sobre estado a medias (ej. V001 sobre V000 fallido).
18. Migración es SQL versionado numerado que lleva la DB de un estado al siguiente en orden (V000 tablespaces+usuarios, V001 tablas). No se editan tras aplicar porque ya corrieron en compañeros; se corrige con migración nueva para mantener mismo orden para todos.
19. `FREEPDB1` es el servicio PDB de trabajo. `FREE`/CDB es raíz admin, SID lleva a otro modo. Todo el curso trabaja en FREEPDB1.
20. SQL*Plus existe en todo servidor Oracle desde 1982, imprescindible a las 3am solo con terminal. SQLcl es moderna del día a día: autocompletado, historial, SQLFORMAT, conexiones guardadas, Liquibase. DBA domina ambas.

## Entorno
21. Oracle/Docker/pipelines son Linux. Git Bash es emulación: convierte rutas /opt a Windows y rompe Docker, necesita winpty para `-it`, no trae free/ss/htop y Java pide password con problemas. En Ubuntu WSL2 todo es Linux real y `docker run -it` funciona.
22. En `/mnt/c` cada operación cruza dos filesystems, Git/Docker lentos, se pierden permisos +x y vuelven CRLF. En `~/oracle-database-lab.` es nativo. bash porque está en todo servidor; zsh es comodidad macOS pero scripts compartidos deben ser bash portable con `#!/usr/bin/env bash`.
