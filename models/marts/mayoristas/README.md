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
int_mayoristas_v3_tickets_por_unidad     (cliente x ticket x unidad_medida -- agregación base)
    -> mayoristas_v3_tickets_unidad      (cliente x ticket x unidad_medida -- C1/C2)
        -> mayoristas_v3_metricas_unidad (cliente x unidad_medida -- umbrales + c1/c2)
            -> mayoristas_v3_resumen     (cliente -- puntaje/nivel final, TABLA DE PRODUCCIÓN de v3)
            -> mayoristas_v3_umbrales    (1 fila x unidad_medida -- referencia de metodología)
```

`int_mayoristas_v3_tickets_por_unidad` se separó de
`mayoristas_v3_tickets_unidad` (donde antes vivía como CTE) después de
que el primer build real colgara la instancia: el cálculo de Q1/Q3 por
`unidad_medida` usaba `PERCENTILE_CONT(...) OVER (PARTITION BY
unidad_medida)`, y con `Unid`+`KILOS` concentrando >99% de los tickets,
esa partición fuerza al motor a repartir el trabajo paralelo de forma
muy despareja (confirmado con `sys.dm_os_tasks`: 3 threads de 40
cargando casi todo, el resto ocioso). Se reemplazó por 4 ramas
independientes (`UNION ALL`, una por unidad_medida) con exactamente la
misma fórmula sobre las mismas filas -- resultado idéntico, pero cada
rama se paraleliza libre por su cuenta en vez de competir por el mismo
carril. Separar la agregación base en su propio modelo evita, además,
que esas 4 ramas más el join final recalculen el `GROUP BY` sobre
`int_ventas_12m` cinco veces.

La corrida real posterior encontró 2 problemas más, ya corregidos:

1. **Error de sintaxis** (`PERCENTILE_CONT` requiere `OVER()` en T-SQL
   siempre, a diferencia de Postgres/Oracle donde puede ser agregado
   simple con `GROUP BY` -- falla con el error 10753 sin `OVER`). Se
   agregó `OVER()` vacío (sin `PARTITION BY`) a cada rama del `UNION
   ALL`, más `DISTINCT` para colapsar las filas repetidas -- no
   reintroduce el problema de skew porque cada rama ya viene filtrada a
   una sola unidad_medida.
2. **`mayoristas_v3_umbrales` armaba un producto cartesiano**: unía
   `mayoristas_v3_tickets_unidad` (grano ticket, millones de filas) con
   `mayoristas_v3_metricas_unidad` (grano cliente, hasta ~1,6M filas)
   directo por `unidad_medida` (solo 4 valores posibles) -- eso arma el
   cruce completo de cada lado antes de que el `GROUP BY` + `MAX()` lo
   colapse de vuelta a 1 fila por unidad, y volvió a colgar la base.
   Corregido sacando primero el `DISTINCT` de cada tabla por separado
   (cada una ya trae un solo valor por unidad_medida) y uniendo recién
   esos dos resultados de 4 filas.

**Estado al cierre de esta sesión**: con los 3 fixes aplicados,
`int_mayoristas_v3_tickets_por_unidad` → `mayoristas_v3_tickets_unidad`
→ `mayoristas_v3_metricas_unidad` → `mayoristas_v3_resumen` corrieron
bien contra la base real (confirmado -- Power BI ya consulta
`mayoristas_v3_resumen` sin problema). `mayoristas_v3_umbrales`, con el
fix del cartesiano aplicado, **todavía no se confirmó que haya
terminado de correr** -- quedó pendiente verificar.

También durante esta sesión se confirmó que `marts_mayoristas.mayoristas_v3_detalle_unidad`
(774.619 filas) es una tabla física que sigue existiendo en la base,
escrita directo por `analisis_mayoristas_v3.ipynb` vía pandas ANTES del
port a dbt -- dbt no la toca ni la actualiza, quedó congelada. Sus 9
columnas son idénticas, mismo nombre y orden, a las de
`mayoristas_v3_metricas_unidad`: es su predecesora directa. Un tablero
de Power BI viejo la sigue consultando directo (`Item="mayoristas_v3_detalle_unidad"`
en Power Query) -- hay que repuntarlo a `mayoristas_v3_metricas_unidad`
antes de borrar la tabla vieja.

`mayoristas_v3_resumen` lee además `int_ventas_12m` directo (no pasa por
`mayoristas_v3_tickets_unidad`) para C3, que es global -- entran todas
las unidades de medida, no solo las 4 con C1/C2.

El notebook (`analisis_mayorista/analisis_mayoristas_v3.ipynb`) ya no
escribe ninguna de estas tablas -- dbt es la fuente. El notebook queda
para la parte exploratoria (boxplots/asimetría/curtosis sobre la mezcla
de unidades, que motivó todo este rediseño) y para leer estas tablas y
validar casos puntuales.
