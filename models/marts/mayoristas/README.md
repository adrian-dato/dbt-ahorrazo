# marts/mayoristas/

Reemplaza `view_ventas_ahorrazo_filtradas_12m` (SQL) + el notebook v2
(reglas Q3 + 1.5×IQR, la metodología ya validada como canónica) de
`analisis_mayorista`. Ver `PLAN_REINGENIERIA.md` en ese repo.

Pendientes (Fase 4.3 de `PLAN_MAESTRO_REINGENIERIA.md`, el proyecto
menos urgente del portfolio — SLA mensual):
- `int_ventas_filtradas_12m.sql` — reemplaza la vista actual (no
  materializada, con `FORMAT()` por fila) como tabla incremental.
- `fct_features_cliente_global.sql` / `fct_features_cliente_sucursal.sql`
  — port SQL de `features_clientes()`/`calcular_metricas()`, hoy en pandas.
- `dim_clientes_mayoristas.sql` — join final con el resultado de
  `clasificar_nivel()` v2 (que se queda en Python, sobre una tabla ya
  chica — ver `analisis_mayorista`), build-and-swap atómico.

v1 (score ML + KMeans/IsolationForest) se archiva como job separado
(`clientes_mayoristas_ml_archive`), no se borra ni se migra a dbt.
