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

## v3 -- metodología corregida, en curso de portarse a dbt

v2 tiene un bug real sin corregir: `upt`/`pct_tickets_grandes` mezclan
`unidades` de TODAS las unidades de medida (kilos, litros, unidades
sueltas, packs) en una sola suma sin sentido (ej. 130 kilos + 697
unidades = "827 unidades"). v3 corrige esto calculando cada criterio por
separado por `unidad_medida` -- desarrollado y validado en
`analisis_mayorista/analisis_mayoristas_v3.ipynb`, todavía **prototipo**
(no reemplaza a v2 como fuente de producción).

Cadena completa, ya portada a dbt (antes vivía entera en el notebook,
escribiendo a mano por pandas):

```
mayoristas_v3_tickets_unidad         (cliente x ticket x unidad_medida -- C1/C2)
    -> mayoristas_v3_metricas_unidad (cliente x unidad_medida -- umbrales + c1/c2)
        -> mayoristas_v3_resumen     (cliente -- puntaje/nivel final, TABLA DE PRODUCCIÓN de v3)
        -> mayoristas_v3_umbrales    (1 fila x unidad_medida -- referencia de metodología)
```

`mayoristas_v3_resumen` lee además `int_ventas_12m` directo (no pasa por
`mayoristas_v3_tickets_unidad`) para C3, que es global -- entran todas
las unidades de medida, no solo las 4 con C1/C2.

El notebook (`analisis_mayorista/analisis_mayoristas_v3.ipynb`) ya no
escribe ninguna de estas tablas -- dbt es la fuente. El notebook queda
para la parte exploratoria (boxplots/asimetría/curtosis sobre la mezcla
de unidades, que motivó todo este rediseño) y para leer estas tablas y
validar casos puntuales.
