# Comandos de dbt_ahorrazo

Referencia para correr dbt contra la base real desde una compu local. El armado
del entorno está en [`README.md`](README.md).

## Activar el entorno

Una vez por sesión de terminal:

```bash
cd dbt_ahorrazo
source activar.sh
```

`activar.sh` hace estos tres pasos:

```bash
source .venv/Scripts/activate    # en WSL o Linux, .venv/bin/activate
set -a && source .env && set +a
export DBT_PROFILES_DIR="$(pwd)"
```

Tiene que ser `source activar.sh` y no `./activar.sh`. Corrido como script, las
variables quedan en una subshell que se descarta al terminar y los comandos `dbt`
siguientes no las ven.

## Los comandos base

| Comando | Qué hace |
|---|---|
| `dbt debug` | Prueba la conexión. El primero a correr cuando algo no funciona. |
| `dbt build` | Seeds, modelos y tests, en orden de dependencias. Sin `--select` recorre el proyecto entero sobre una fact de más de 238 millones de filas, así que conviene acotarlo casi siempre. |
| `dbt run` | Igual que `dbt build` pero sin los tests. |
| `dbt test` | Solo los tests, sobre modelos ya construidos. |
| `dbt compile` | Resuelve el Jinja a SQL plano sin ejecutar nada. Queda en `target/compiled/`. |
| `dbt show` | Compila y ejecuta, mostrando el resultado en la terminal sin persistir nada. Funciona con modelos y con analyses. |
| `dbt docs generate` + `dbt docs serve` | Catálogo y lineage navegables. |

## Cómo acotar qué se corre

```bash
# Un modelo puntual
dbt build --select mayoristas_v3_resumen

# Un modelo con todo lo que necesita para construirse
dbt build --select +mayoristas_v3_resumen

# Un modelo con todo lo que depende de él
dbt build --select mayoristas_v3_resumen+

# Todo el linaje, hacia arriba y hacia abajo
dbt build --select +mayoristas_v3_resumen+

# Una carpeta entera
dbt build --select staging
dbt build --select marts.canibalizacion

# Por tag de proyecto, que es lo que usan los DAGs
dbt build --select +tag:mayoristas
dbt build --select +tag:top_300
dbt build --select +tag:canibalizacion

# Excluir algo de una selección más amplia
dbt build --select staging --exclude stg_clientes
```

Los tags están declarados a nivel carpeta en `dbt_project.yml`, así que un modelo
nuevo en `marts/<proyecto>/` queda incluido sin tocar nada más. Es la forma
preferible de seleccionar un proyecto completo: apuntar a un modelo puntual deja
afuera cualquier rama que no sea ancestro de ese modelo.

## Reconstruir Mayoristas

La cadena entera, que es lo que corre el DAG mensual:

```bash
dbt test --select assert_ventas_actualizada_mes_cerrado
dbt build --select +tag:mayoristas
```

El test va primero y es una puerta, no un trámite. Compara el máximo de
`Ventas_Ahorrazo` contra el último día del mes cerrado. Si avisa, la fuente
todavía no terminó de cargar el mes y un build recalcularía la clasificación
sobre un período incompleto: todos los cortes se moverían por un mes a medio
cargar y no por el negocio. Está en `severity: warn`, así que no frena nada por
sí solo, hay que mirarlo.

Cuando un modelo cambia de tabla a vista o al revés, conviene borrar el objeto
anterior antes del build. dbt no siempre hace esa conversión limpia:

```sql
drop table if exists marts_mayoristas.mayoristas_v3_tickets_unidad;
```

## Modelos incrementales

`int_clientes_mapeo_limpio` y `fct_ventas_36m` solo reprocesan las filas
recientes en una corrida normal. Hay que forzar la reconstrucción completa en dos
situaciones:

- La primera vez, si la tabla todavía no existe. Ahí dbt lo hace solo, sin flag.
- Cuando cambia el SQL del modelo. dbt no reconstruye el histórico por su cuenta
  y no avisa: hay que pedirlo.

```bash
dbt build --select fct_ventas_36m --full-refresh
```

`int_clientes_mapeo_limpio` tarda entre 47 y 67 minutos en `--full-refresh`. Es
el modelo más lento del proyecto.

## Snapshots

```bash
dbt snapshot --select dim_cliente_tipo_migracion_snapshot
```

Un `dbt build` con selector no corre los snapshots. Sin selector sí los incluye
al final. Y `dbt snapshot --full-refresh` borra la historia acumulada, que no se
puede recuperar.

## Analyses

Los archivos de `analyses/` se compilan pero no se ejecutan solos. `dbt show` los
corre directo:

```bash
dbt show --select monitorear_ejecucion_actual
dbt show --select perfilar_calidad_cliente_id --limit 20
```

Algunos tienen varios `select` separados por punto y coma, y ahí `dbt show`
devuelve una sola grilla -- `metodologia_mayoristas_v3` es el caso extremo,
varias decenas de consultas en un solo archivo, divididas en secciones. Para
esos conviene `dbt compile --select <nombre>` y correr a mano el archivo que
queda en `target/compiled/`. Los que están escritos en SQL plano, sin `ref()`,
se pegan directo en el cliente de SQL.

Para una consulta de una sola vez que no amerita un archivo:

```bash
dbt show --inline "select top 10 * from {{ ref('mayoristas_v3_umbrales') }}"
```

## Tests

```bash
# Todos los tests de un modelo
dbt test --select mayoristas_v3_resumen

# Un test puntual de los que viven en tests/
dbt test --select assert_unidades_con_variancia
```

Hay tres tests propios además de los declarados en los `schema.yml`:

`assert_ventas_actualizada_mes_cerrado` avisa si la fuente no terminó de cargar
el mes cerrado más reciente. No usa `dbt source freshness` porque ese mecanismo
solo admite umbrales relativos del tipo "hace N días" y acá el corte es de
calendario.

`assert_unidades_con_variancia` avisa qué unidad de medida tiene Q1 igual a Q3, y
por lo tanto está usando el fallback del corte de factura grande.

`assert_cliente_id_limpio_no_explota` revisa que la heurística de colapso de
identificadores no esté fusionando clientes distintos.

Los tres están en `severity: warn` a propósito: una falla de DAG tiene que
significar un problema real de ejecución, no una alerta de contenido. El DAG
diario lee el resultado en `run_results.json` y manda su propio mail.

## Dónde mirar cuándo algo no cierra

Antes que nada, el período que tiene cada tabla:

```bash
dbt compile --select verificar_ventana_de_los_marts
```

Todas las tablas de la cadena tienen que cubrir el mismo rango de fechas. La que
no coincida es la que no se reconstruyó con las otras, y es donde van a aparecer
clientes sin clasificación o fechas fuera del calendario en el tablero.

No sirve mirar `create_date` ni `modify_date` en `sys.objects`: esas columnas
reflejan cambios de estructura y no de contenido, así que una tabla recargada
entera puede seguir mostrando la fecha de la semana pasada.
