"""Lee target/run_results.json (generado por dbt en cada invocación) y
imprime un resumen de una línea por nodo: estado, tiempo, y el primer
renglón del error si falló. Se invoca automáticamente desde el wrapper
de `dbt` en activar.sh -- no hace falta correrlo a mano.
"""
import json
import sys
from pathlib import Path

run_results_path = Path("target/run_results.json")

if not run_results_path.exists():
    print("No se encontró target/run_results.json (¿el comando no llegó a ejecutar ningún nodo?).")
    sys.exit(0)

with run_results_path.open(encoding="utf-8") as f:
    data = json.load(f)

resultados = data.get("results", [])
if not resultados:
    print("run_results.json existe pero no tiene nodos ejecutados.")
    sys.exit(0)

conteo = {}
for r in resultados:
    status = r.get("status", "unknown")
    conteo[status] = conteo.get(status, 0) + 1
    nombre = r.get("unique_id", "?").split(".")[-1]
    tiempo = r.get("execution_time", 0)
    print(f"{status.upper():8} {nombre:60} {tiempo:6.2f}s")
    if status in ("error", "fail"):
        mensaje = (r.get("message") or "").strip()
        if mensaje:
            primera_linea = mensaje.splitlines()[0]
            print(f"         -> {primera_linea}")

print()
print("Resumen:", ", ".join(f"{k}={v}" for k, v in sorted(conteo.items())))
