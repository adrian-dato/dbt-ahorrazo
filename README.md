# dbt_ahorrazo

Proyecto dbt **compartido** por los 3 proyectos de negocio del portfolio de
datos de Ahorrazo:

- `canibalizacion_ahorrazo`
- `top_300_productos`
- `analisis_mayorista`

## Por qué este repo existe

Los 3 proyectos leen las mismas tablas base en SQL Server
(`Ventas_Ahorrazo`, `clientes_mapeo`, `clientes_limpio`, `productos`) y,
hasta ahora, cada uno reimplementaba por separado la limpieza de esas
tablas y sus reglas de negocio (exclusión de categorías, colapso de
`cliente_id` duplicados) — con el tiempo, de forma inconsistente entre sí.

Este repo centraliza esa capa de transformación una sola vez:

```
sources (SQL Server, declarado 1 vez)
   → staging/       (1:1 tipado/limpio por tabla fuente)
   → intermediate/  (reglas de negocio COMPARTIDAS: limpieza de cliente,
                      exclusiones de venta — fuente única de verdad)
   → marts/<proyecto>/  (específico de cada proyecto de negocio)
```

`ref()` entre `staging`/`intermediate` y cada `marts/<proyecto>` solo
funciona porque todo vive en el mismo proyecto dbt — por eso este es un
repo nuevo y no 3 proyectos dbt separados (dbt Core no resuelve `ref()`
entre repos sin dbt Mesh, de pago). Los 4 repos de negocio existentes
quedan livianos: solo el Python específico de cada uno (scoring,
notebooks de exploración, DAGs de Airflow), consumiendo por nombre las
tablas que publica este repo.

Contexto completo y diagnóstico a nivel portfolio:
[`../PLAN_MAESTRO_REINGENIERIA.md`](../PLAN_MAESTRO_REINGENIERIA.md).

## Estado

*(Resumen ejecutivo — para el detalle comando por comando y qué falta
puntualmente, ver [`PENDIENTES.md`](PENDIENTES.md); para los diagramas
de dependencias y el orden de ejecución real, ver
[`ARQUITECTURA.md`](ARQUITECTURA.md).)*

Confirmado contra la base real: la fundación (staging + `fct_ventas_36m`),
la migración de `clientes_mapeo_limpio` (con 2 bugs reales del proceso
legacy encontrados y corregidos en el camino), las reglas de negocio
compartidas (`int_ventas_elegibles`, `int_ventas_12m`) y los 3 marts
por proyecto: **Canibalización** (v1, `dim_cliente_tipo_migracion`),
**Top 300 Productos** (`top300_ranking`) y **Clientes Mayoristas**
(`dim_clientes_mayoristas`), con snapshots SCD2 (`dbt snapshot`) donde
corresponde.

**Canibalización v3** (metodología nueva, eventos de migración
cliente→sucursal — vía paralela a v1, no la reemplaza) tiene el código
portado y listo, pero todavía no corrió contra la base real: es el
próximo paso técnico del repo.

**Mayoristas v3** (metodología nueva, corrige un bug real de v2 que
mezclaba unidades de medida distintas en un solo número — vía paralela
a v2, no la reemplaza todavía) tiene el código portado y ya corrió
contra la base real hasta `mayoristas_v3_resumen`. La primera corrida
encontró 3 problemas de performance/sintaxis en las queries (una de
ellas llegó a colgar la instancia compartida de SQL Server), ya
corregidos — el último modelo de la cadena (`mayoristas_v3_umbrales`)
tiene el fix aplicado pero sin confirmar todavía que corra limpio. Ver
`models/marts/mayoristas/README.md` para el detalle.

**Orquestación**: los 3 proyectos ya corren en producción vía Airflow,
en un repo separado
([`orquestacion_ahorrazo`](../orquestacion_ahorrazo), sibling de este)
que se suma al Airflow dockerizado que ya opera el equipo de Stock en
el mismo Windows Server — DAGs propios e independientes, sin acoplarse
a la orquestación de Stock. Ver la sección "Orquestación (Airflow)" en
[`ARQUITECTURA.md`](ARQUITECTURA.md) para el detalle de horarios.

Falta: correr Canibalización v3 contra la base real, confirmar el
mapeo de consumidores (Power BI, otros scripts) antes de apagar
cualquier proceso legacy, y un puñado de decisiones de negocio (no
técnicas) documentadas en `PENDIENTES.md`.

## Setup local

Validado de punta a punta (conexión real + build real) desde una compu
local con Python 3.12 + Git Bash, conectada por VPN al server:

1. `python -m venv .venv` (usar 3.12/3.13 -- dbt todavía no soporta bien
   versiones muy nuevas de Python; en Windows con varias versiones
   instaladas, `py -3.12 -m venv .venv`).
2. `source .venv/Scripts/activate` (Windows: `Scripts/`, no `bin/`) y
   `pip install -r requirements.txt` (instala `dbt-core` + `dbt-sqlserver`
   + `pyodbc`).
3. Copiar `profiles.yml.example` a `profiles.yml` y crear `.env` (mismos
   nombres de variable que ya usa `conexion_bd.py` en los otros repos del
   portfolio: `DB_SERVER`, `DB_DATABASE`, `DB_USER`, `DB_PASSWORD`) --
   ambos en la raíz del repo, ya gitignorados.
4. `profiles.yml` vive junto al proyecto, no en `~/.dbt/` -- hay que
   decirle a dbt que busque ahí con `DBT_PROFILES_DIR`. `source activar.sh`
   hace esto (y activa el venv y carga `.env`) en un solo paso -- ver
   `activar.sh` si hace falta adaptarlo a otro entorno (ej. WSL).
5. `dbt debug` para confirmar la conexión.

Para la lista completa de comandos (correr modelos, tests, analyses,
selectors, `--full-refresh`), ver **[`COMANDOS.md`](COMANDOS.md)**.

Con `.env`/`profiles.yml` en la misma carpeta que el resto del proyecto
(ambos gitignorados), copiar el repo entero a otro server (scp/rsync
después de un `git pull`) alcanza para que dbt funcione ahí también --
no hace falta recrear nada por separado en `~/.dbt/`. Al correr desde
Airflow (ya el caso en producción, ver `orquestacion_ahorrazo`),
`DBT_PROFILES_DIR` se setea como variable de entorno de la tarea (o,
mejor todavía, migrar las credenciales a Airflow Connections en vez de
a este `.env` -- ver plan maestro, sección de secretos).

## Convenciones de nombres

- `stg_*` — 1:1 con la fuente, tipado/limpio, materializado como `view`.
- `int_*` — reglas de negocio compartidas, materializado `incremental`.
- `fct_*` / `dim_*` — marts finales por proyecto, materializado `table`
  (build-and-swap atómico, gestionado por dbt).
