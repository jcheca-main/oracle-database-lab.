#!/usr/bin/env bash
# scripts/deployment/env/01-verificar-requisitos.sh
echo "== Sistema operativo y arquitectura =="
uname -s
uname -m
grep -qi microsoft /proc/version 2>/dev/null && echo "Entorno: Ubuntu en WSL 2"
[ -f /etc/os-release ] && grep PRETTY_NAME /etc/os-release
echo
echo "== Shell por defecto =="
echo "$SHELL"
echo
echo "== Espacio libre en disco (unidad del repositorio) =="
df -h .
echo
echo "== Memoria disponible para Linux y Docker =="
case "$(uname -s)" in
 Linux*) free -h ;;
 Darwin*) echo "$(( $(sysctl -n hw.memsize) / 1073741824 )) GB" ;;
esac
echo
echo "== Herramientas de trabajo (Parte 0) =="
for t in git gh curl wget unzip jq tree htop tmux shellcheck; do
 command -v "$t" > /dev/null && echo "OK $t" || echo "FALTA $t"
done
echo
echo "== Git =="
git --version
git config --global user.email
