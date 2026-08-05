# marts/mayoristas/

Reemplaza `analisis_mayoristas_v2.ipynb` de `analisis_mayorista` -- el
notebook v2 (reglas Q3 + 1.5×IQR), la metodología ya validada como
canónica frente al v1 (score ML). Lógica leída del notebook real, no
adivinada.

## Estado

- `int_mayoristas_umbral_ticket_grande`, `int_mayoristas_metricas_cliente`,
  `dim_clientes_mayoristas` -- escritos. Sin correr todavía contra la
  base real.
- `int_ventas_filtradas_12m` (nombrado así en el plan original) ya
  estaba resuelto de antes: es `int_ventas_12m` en `intermediate/`,
  compartido con Top 300 -- no se duplicó acá.

## Desvío respecto al plan original

El plan original (`PLAN_MAESTRO_REINGENIERIA.md`, y el propio
`PLAN_REINGENIERIA.md` de `analisis_mayorista`) preveía que
`clasificar_nivel()` se quedara en Python ("scoring sobre una tabla ya
chica"). Acá se portó completo a SQL (`dim_clientes_mayoristas.sql`,
vía `PERCENTILE_CONT` para los umbrales Q3 dinámicos) porque la lógica
-- comparar cada métrica contra un umbral y sumar puntos -- se expresa
igual de bien en SQL, sin necesitar un paso Python aparte. No cambia
ningún resultado (mismo cálculo, mismos umbrales), solo dónde corre --
push-down completo a SQL Server, coherente con el principio rector del
plan maestro ("el cómputo pesado vive en SQL Server, no en Python").

v1 (score ML + KMeans/IsolationForest) se archiva como job separado en
`analisis_mayorista`, no se migra a dbt.
