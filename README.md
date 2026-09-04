# dbt_ahorrazo

Proyecto dbt compartido por los tres proyectos de datos de Ahorrazo:
`canibalizacion_ahorrazo`, `top_300_productos` y `analisis_mayorista`.

## Por qué este repo existe

Los tres proyectos leen las mismas tablas base en SQL Server (`Ventas_Ahorrazo`,
`clientes_mapeo`, `clientes_limpio`, `productos`). Antes, cada uno implementaba
por su cuenta la limpieza de esas tablas y las reglas de negocio: qué categorías
se excluyen, cómo se colapsan los `cliente_id` duplicados. Con el tiempo las tres
implementaciones se fueron separando entre sí y devolvían resultados distintos
para la misma pregunta.

Este repo tiene esa capa una sola vez:

```
sources (SQL Server, declarados una vez)
   → staging/          tipado y limpieza, una tabla por fuente
   → intermediate/     reglas de negocio compartidas por los tres proyectos
   → marts/<proyecto>/ lo específico de cada proyecto
```

Todo vive en un mismo proyecto dbt porque `ref()` solo resuelve dentro de un
proyecto: separarlo en tres proyectos dbt requeriría dbt Mesh, que es pago. Los
repos de negocio quedan livianos, con el Python propio de cada uno (scoring,
notebooks de exploración, DAGs) consumiendo por nombre las tablas que publica
este repo.

## Estado

Los diagramas de dependencias y el orden de ejecución están en
[`ARQUITECTURA.md`](ARQUITECTURA.md).

Corriendo en producción contra la base real: la capa de staging, la limpieza de
clientes, las reglas de venta compartidas (`int_ventas_elegibles`,
`int_ventas_12m`, `int_ventas_12m_tabla`) y los tres marts de negocio.

**Clientes Mayoristas** clasifica a los clientes con la metodología v3, que mide
cada unidad de medida contra su propia vara. La versión anterior se eliminó del
repo cuando se hizo el cutover; los objetos que dejó en la base se dan de baja
con `analyses/limpiar_objetos_mayoristas_v2.sql`.

**Top 300 Productos** publica `top300_ranking` semanalmente.

**Canibalización** tiene dos metodologías conviviendo: la v1
(`dim_cliente_tipo_migracion`) y la v3, que trabaja con eventos de migración
entre sucursales. El DAG semanal reconstruye solo la cadena de la v1, así que los
modelos de la v3 quedan sin actualizar entre corridas manuales. Resolverlo son
dos decisiones separadas: cambiar el selector del DAG a `+tag:canibalizacion`,
que no depende de validar nada, y el cutover de v1 a v3, que sí.

**Orquestación**: los tres proyectos corren desde Airflow, en el repo
[`orquestacion_ahorrazo`](../orquestacion_ahorrazo). Ver la sección de
orquestación en `ARQUITECTURA.md` para los horarios.

## Setup local

Probado de punta a punta con Python 3.12 y Git Bash, conectado por VPN al server.

1. `python -m venv .venv`. Conviene 3.12 o 3.13: dbt todavía no acompaña las
   versiones más nuevas de Python. En Windows con varias instaladas,
   `py -3.12 -m venv .venv`.
2. `source .venv/Scripts/activate` (en Windows la carpeta es `Scripts/`) y
   `pip install -r requirements.txt`, que trae `dbt-core`, `dbt-sqlserver` y
   `pyodbc`.
3. Copiar `profiles.yml.example` a `profiles.yml` y crear `.env` con
   `DB_SERVER`, `DB_DATABASE`, `DB_USER` y `DB_PASSWORD`, los mismos nombres que
   usa `conexion_bd.py` en los otros repos. Los dos archivos van en la raíz y ya
   están en el `.gitignore`.
4. `profiles.yml` vive junto al proyecto y no en `~/.dbt/`, así que hay que
   apuntarle a dbt con `DBT_PROFILES_DIR`. `source activar.sh` activa el entorno,
   carga el `.env` y setea esa variable en un solo paso.
5. `dbt debug` para confirmar la conexión.

Los comandos de uso diario están en [`COMANDOS.md`](COMANDOS.md).

Como `.env` y `profiles.yml` viven en la misma carpeta que el proyecto, copiar el
repo entero a otro server alcanza para que dbt funcione ahí. Al correr desde
Airflow, `DBT_PROFILES_DIR` se setea como variable de entorno de la tarea. Migrar
esas credenciales a Airflow Connections queda como mejora pendiente.

## Convenciones de nombres

| Prefijo | Qué es | Materialización |
|---|---|---|
| `stg_*` | Una tabla por fuente, tipada y limpia | `view` |
| `int_*` | Reglas de negocio compartidas | según el modelo |
| `fct_*` / `dim_*` | Marts finales de cada proyecto | `table` |

Los modelos de `intermediate/` no comparten materialización: cada uno declara la
suya con `{{ config(...) }}`, porque no todos tocan la fact de 238 millones de
filas. Los de `marts/` sí, con `table` a nivel carpeta.
