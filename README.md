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

Contexto completo, diagnóstico y plan de fases:
[`../PLAN_MAESTRO_REINGENIERIA.md`](../PLAN_MAESTRO_REINGENIERIA.md).

## Estado

**Fase 1 (fundación) — hecha y validada contra la base real.** Portado
desde `canibalizacion_ahorrazo` (la implementación más madura del
portfolio, sin cambios de lógica salvo el renombre de la var
`meses_ventana` -> `meses_ventana_canibalizacion`): `stg_ventas`,
`stg_productos`, `stg_clientes_mapeo`, `stg_clientes_limpio`,
`fct_ventas_36m`, y el seed `dim_sucursal_mapeo`. Nuevo en este repo:
`stg_clientes` (sobre `dbo.Clientes`). `dbt build --select staging
fct_ventas_36m` corre limpio de punta a punta contra la base real
(20/20 tests, `fct_ventas_36m` construido en `dbt_dev`) -- confirma que
la estrategia incremental (`delete+insert`) y el adaptador
`dbt-sqlserver` funcionan en este entorno puntual. En el camino se
encontraron y resolvieron dos cosas reales: el server usa certificado
autofirmado (hace falta `trust_cert: true`, ver `profiles.yml.example`)
y `Ventas_Ahorrazo` tenía 2 filas con `cliente_id` NULL (ventas de
mostrador anónimas, ya excluidas en `stg_ventas`).

**Fase 2 (migrar `clientes_mapeo_limpio`) — modelos hechos, validación
pendiente.** `int_clientes_normalizados`, `int_clientes_mapeo_limpio`
(incremental) e `int_clientes_limpio` (`table`) ya están escritos,
portando regla por regla la limpieza de `dbo.Clientes` del proceso
legacy (ver `models/intermediate/README.md`). **Corren en paralelo al
proceso legacy** — `stg_clientes_mapeo`/`stg_clientes_limpio` siguen
apuntando a las tablas viejas hasta validar con
`analyses/validar_clientes_mapeo_limpio.sql` que el resultado coincide.

**Pendiente**: reglas de exclusión compartidas (Fase 3, `int_ventas_elegibles`)
y el resto de los marts por proyecto (Fase 4). Cada carpeta de `models/`
tiene un `README.md` con el detalle de qué falta y en qué fase.

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
no hace falta recrear nada por separado en `~/.dbt/`. Si en algún
momento se corre desde Airflow (Fase 5), setear `DBT_PROFILES_DIR` como
variable de entorno de la tarea (o, mejor todavía en ese momento, migrar
las credenciales a Airflow Connections en vez de a este `.env` -- ver
plan maestro, sección de secretos).

## Convenciones de nombres

- `stg_*` — 1:1 con la fuente, tipado/limpio, materializado como `view`.
- `int_*` — reglas de negocio compartidas, materializado `incremental`.
- `fct_*` / `dim_*` — marts finales por proyecto, materializado `table`
  (build-and-swap atómico, gestionado por dbt).
