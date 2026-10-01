#!/usr/bin/env bash
# scripts/deployment/env/09-verificar-java-sqlcl.sh
echo "== Java =="
java -version 2>&1
echo
echo "== JAVA_HOME =="
echo "$JAVA_HOME"
echo
echo "== SQLcl =="
sql -version
