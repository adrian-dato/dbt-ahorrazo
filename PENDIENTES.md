# Pendientes

Una sola lista de qué falta validar/decidir, para no perder el hilo bajo
presión de tiempo. Ver `../PLAN_MAESTRO_REINGENIERIA.md` para el plan
completo por fases.

## Fase 2 — clientes_mapeo_limpio: NO CONFIRMADO TODAVÍA

- [ ] Terminar `dbt build --select int_clientes_normalizados int_clientes_mapeo_limpio int_clientes_limpio --full-refresh`
- [ ] Correr `analyses/validar_clientes_mapeo_limpio.sql`:
  - `conteo_solo_nuevo` **tiene que dar 0** (si no, hay un bug real, no una mejora).
  - `conteo_valor_distinto` / `conteo_solo_legacy` > 0 es esperado -- confirmar
    (sección 2 del archivo) que las filas que difieren encajan en los
    patrones ya identificados (símbolos en los extremos, separador raro
    + 1 dígito, clientes no identificables excluidos) y no algo nuevo.
- [ ] **Recién después de validar**: repuntar `stg_clientes_mapeo`/`stg_clientes_limpio`
  de sus `source()` actuales a `ref('int_clientes_mapeo_limpio')`/`ref('int_clientes_limpio')`.
- **No usar `int_clientes_mapeo_limpio`/`int_clientes_limpio` desde ningún mart nuevo hasta validar esto.**

## Fase 3 — reglas de exclusión compartidas (`int_ventas_elegibles`)

- [x] Modelo escrito + seed `productos_excluidos.csv` (lista real, sacada
  de `top_300_productos.ipynb`, no inventada).
- [ ] Sin correr todavía contra la base real (falta `dbt build --select
  int_ventas_elegibles`, no depende del build en curso de Fase 2).
- [ ] Limpieza opcional, no bloqueante: migrar `fct_ventas_36m` para que
  use `ref('int_ventas_elegibles')` en vez de su copia inline de las
  mismas reglas.

## Fase 4 — marts por proyecto

- [ ] Canibalización: `fct_ventas_36m_pivotado`, `dim_cliente_tipo_migracion`.
- [ ] Top 300: todo (`int_ventas_mensual_producto_pdv`, `top300_ranking`).
- [ ] Mayoristas: todo (`int_ventas_filtradas_12m`, `fct_features_cliente_*`).
