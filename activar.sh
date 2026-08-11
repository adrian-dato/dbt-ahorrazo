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

# Wrapper de dbt: cada comando que corras (build/run/snapshot/etc) queda
# archivado en logs/runs/<timestamp>.log (la salida completa, igual a la
# de siempre) + logs/runs/<timestamp>_resumen.txt (una línea por modelo/
# test con su estado y tiempo, y el mensaje de error si falló --
# ver scripts/resumen_run.py). No cambia en nada cómo se usa dbt, solo
# queda historial de cada corrida en vez de perderse en la consola.
dbt() {
    local ts before_ts exit_code
    #timestamp para el log de esta corrida
    ts=$(date +%Y%m%dT%H%M%S)
    mkdir -p logs/runs
    # Capturado ANTES de correr: si dbt falla temprano (ej. error de
    # conexión, antes de ejecutar cualquier nodo) run_results.json no se
    # reescribe -- sin este chequeo, el resumen mostraría el resultado de
    # la corrida ANTERIOR como si fuera de esta, en silencio.
    before_ts=$(date +%s)
    command dbt "$@" 2>&1 | tee "logs/runs/${ts}.log"
    exit_code=${PIPESTATUS[0]}
    echo ""
    if [ -f target/run_results.json ] && [ "$(stat -c %Y target/run_results.json 2>/dev/null)" -ge "$before_ts" ]; then
        python scripts/resumen_run.py > "logs/runs/${ts}_resumen.txt"
        echo "--- Resumen (logs/runs/${ts}_resumen.txt) ---"
        cat "logs/runs/${ts}_resumen.txt"
    else
        echo "Sin resumen: esta corrida no llegó a generar/actualizar run_results.json (falló antes de ejecutar cualquier nodo -- ver logs/runs/${ts}.log)." | tee "logs/runs/${ts}_resumen.txt" > /dev/null
        echo "Sin resumen: esta corrida no llegó a generar/actualizar run_results.json (falló antes de ejecutar cualquier nodo -- ver logs/runs/${ts}.log)."
    fi
    return $exit_code
}

echo "Entorno listo (venv activado, .env cargado, DBT_PROFILES_DIR=$DBT_PROFILES_DIR)"
