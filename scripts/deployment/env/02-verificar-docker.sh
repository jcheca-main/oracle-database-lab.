#!/usr/bin/env bash
# scripts/deployment/env/02-verificar-docker.sh
echo "== Cliente y servidor de Docker =="
docker version
echo
echo "== Prueba real: crear, ejecutar y eliminar un contenedor =="
docker run --rm hello-world
