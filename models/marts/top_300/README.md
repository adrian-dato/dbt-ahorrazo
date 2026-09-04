# marts/top_300/

Reemplaza a `top_300_productos.ipynb`. La lógica se portó leyendo el notebook
original: los KPIs, la normalización logarítmica, el Puntaje Final y los buckets
de unidades por ticket.

`int_top300_kpis` calcula los indicadores por producto y `top300_ranking` arma el
ranking final. Los dos corren semanalmente desde el DAG de Airflow, que ejecuta
`dbt build --select +top300_ranking`.

Queda pendiente enriquecer el ranking con metadata de producto (nombre, categoría
y precio desde `dbo.Productos`). El notebook lo hacía en una celda al final y esa
parte todavía no se portó.

El orquestador de Python que revisa bloqueos antes de correr y notifica el
resultado vive en el repo `top_300_productos`. Este repo es solo la capa dbt.
