# Comandos — dbt_ahorrazo

Referencia rápida para correr dbt contra la base real desde una compu
local (venv + `.env` + `profiles.yml` en la raíz del repo, ver
`README.md` → "Setup local" para el detalle de cómo quedó armado).

## 0. Activar el entorno (una vez por sesión nueva de terminal)

```bash
cd dbt_ahorrazo
source activar.sh
```

Hace lo mismo que estos 4 pasos (por si `activar.sh` no está disponible
o hay que adaptarlo a otro entorno, ej. WSL más adelante):

```bash
source .venv/Scripts/activate    # en WSL/Linux: .venv/bin/activate
set -a && source .env && set +a
export DBT_PROFILES_DIR="$(pwd)"
```

**Importante**: tiene que ser `source activar.sh`, no `./activar.sh` — si
se corre como script aparte, las variables quedan en una subshell
descartable y no le llegan a los comandos `dbt` siguientes.

## 1. Comandos básicos

| Comando | Qué hace |
|---|---|
| `dbt debug` | Prueba la conexión a la base. Primer comando para confirmar que todo está bien configurado. |
| `dbt build` | Corre TODO (seeds + models + tests) en orden de dependencias. Sobre una fact de 238M+ filas, correrlo sin acotar puede tardar bastante — preferir `--select` casi siempre. |
| `dbt run` | Como `dbt build`, pero solo modelos (sin tests). |
| `dbt test` | Solo corre tests, sobre modelos ya construidos. |
| `dbt compile` | Resuelve el Jinja/`ref()`/`source()` a SQL plano, sin ejecutar nada contra la base. El resultado queda en `target/compiled/`. |
| `dbt show` | Compila Y ejecuta, mostrando el resultado en la terminal (no persiste nada). Sirve tanto para modelos como para `analyses/`. |
| `dbt docs generate` + `dbt docs serve` | Genera y sirve el catálogo/lineage navegable del proyecto (útil más adelante, no urgente ahora). |

## 2. Selectors — cómo elegir qué correr

Todos estos comandos aceptan `--select` (o `-s`) para acotar el alcance.
Sin `--select`, corren TODO el proyecto.

```bash
# Un modelo puntual
dbt build --select stg_ventas

# Varios modelos a la vez
dbt build --select staging fct_ventas_36m

# Toda una carpeta/capa (funciona porque el nombre de carpeta es parte
# del path del modelo)
dbt build --select staging
dbt build --select marts.canibalizacion

# Un modelo + todo lo que necesita para construirse (upstream, el "+"
# va ANTES del nombre)
dbt build --select +fct_ventas_36m

# Un modelo + todo lo que depende de él (downstream, el "+" va DESPUÉS)
dbt build --select fct_ventas_36m+

# Todo el linaje completo (arriba y abajo)
dbt build --select +fct_ventas_36m+

# Por tag de proyecto (canibalizacion/top_300/mayoristas -- ya
# configurado en dbt_project.yml para todo lo que esté bajo marts/)
dbt build --select tag:canibalizacion

# Excluir algo puntual de una selección más amplia
dbt build --select staging --exclude stg_clientes
```

## 3. Modelos incrementales — cuándo usar `--full-refresh`

`fct_ventas_36m`, `int_clientes_mapeo_limpio` (y los que se agreguen
después) son incrementales: por default solo reprocesan el delta
reciente. Hay que forzar reconstrucción completa con `--full-refresh`:

- La primera vez que se corre un modelo incremental nuevo (si la tabla
  todavía no existe, dbt hace full build automáticamente -- no hace
  falta el flag la primera vez).
- Cuando cambia el SQL de un modelo incremental ya construido -- dbt
  NO reconstruye el histórico solo, hay que pedirlo explícito.

```bash
dbt build --select fct_ventas_36m --full-refresh
```

## 4. Analyses (`analyses/*.sql`) — no son modelos, no corren con `dbt build`

Confirmado que `dbt show` funciona directo sobre analyses, igual que
sobre modelos (no hace falta copiar/pegar el SQL compilado a mano):

```bash
dbt show --select perfilar_calidad_cliente_id --limit 20
dbt show --select validar_clientes_mapeo_limpio
```

Para consultas ad-hoc de una sola vez que no ameritan un archivo nuevo
en `analyses/`, `--inline` con el SQL directo (podés usar `{{ ref(...) }}`
/ `{{ source(...) }}` adentro):

```bash
dbt show --inline "select top 10 * from {{ source('dato_solutions', 'Ventas_Ahorrazo') }} where cliente_id is null"
```

## 5. Tests

```bash
# Todos los tests de un modelo puntual
dbt test --select fct_ventas_36m

# Un test custom puntual (los archivos sueltos en tests/)
dbt test --select assert_cliente_id_limpio_no_explota
```

## 6. Ya corrimos esto contra la base real (referencia de lo hecho)

```bash
dbt debug
dbt build --select staging fct_ventas_36m
dbt show --select perfilar_calidad_cliente_id --limit 20
```

Resultado: staging + `fct_ventas_36m` construidos en `dbt_dev` (schema de
desarrollo, no toca tablas de producción), 20/20 tests en verde. El
perfilado de calidad de `cliente_id` mostró 51 casos raros (19 con
caracteres no contemplados + 32 que quedan vacíos tras limpiar) sobre
800.930 ids totales -- pendiente de revisar esos casos puntuales antes
de dar por buena la limpieza del todo.
