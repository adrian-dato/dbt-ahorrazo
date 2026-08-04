#!/usr/bin/env bash
# Cargar con "source activar.sh" -- NO "./activar.sh" (tiene que modificar
# la shell actual para que el venv y las variables queden activas, correrlo
# como script aparte lo haría en una subshell descartable).
#
# Deja todo listo para correr cualquier comando dbt desde esta carpeta.

source .venv/Scripts/activate
set -a
source .env
set +a
export DBT_PROFILES_DIR="$(pwd)"

echo "Entorno listo (venv activado, .env cargado, DBT_PROFILES_DIR=$DBT_PROFILES_DIR)"
