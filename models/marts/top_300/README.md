# marts/top_300/

Reemplaza `top_300_productos.ipynb` de `top_300_productos`. Lógica
portada leyendo el notebook real (KPIs, normalización logarítmica,
Puntaje Final, buckets de unidades por ticket) -- no adivinada.

## Estado

- `int_top300_kpis` + `top300_ranking` -- escritos. Sin correr todavía
  contra la base real.
- **Pendiente, no bloqueante**: enriquecer con metadata de producto
  (nombre/categoria/precio desde `dbo.Productos`) -- el notebook lo hace
  en una celda aparte al final, no portado todavía.
- El orquestador Python delgado (pre-flight de bloqueos + invocación de
  `dbt build` + notificación, diseñado en `PROPUESTA_REINGENIERIA.md` de
  `top_300_productos`) vive en ese repo, no acá -- este repo es solo la
  capa dbt.
