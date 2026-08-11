# Pendientes

Estado real de la migración a `dbt_ahorrazo`, para que cualquier
conversación/persona pueda retomar sin releer todo el historial. Ver
`../PLAN_MAESTRO_REINGENIERIA.md` para el plan completo por fases y la
sección "Estado de ejecución" ahí para el resumen a nivel portfolio. Ver
`ARQUITECTURA.md` para los diagramas de dependencias por proyecto y el
orden de ejecución real.

## Para retomar ahora mismo

-1. **Alerta de frescura agregada** sobre el source `Ventas_Ahorrazo`
   (`models/staging/_staging__sources.yml`): `warn_after: 7 days` sobre
   `fecha_venta`, sin `error_after` a propósito -- no bloqueante, solo
   queda registrado. Se activa corriendo `dbt source freshness` (comando
   aparte, no corre dentro de `dbt build`) -- todavía no se corrió ni una
   vez. Correrlo con una cadencia real (semanal como mínimo) es tarea de
   Fase 5 (Airflow); por ahora queda la definición lista pero sin
   automatizar.
0. **`dbt build --select +top300_ranking` -- CONFIRMADO, 32/32 PASS**
   (corrida del 2026-08-05, 55 min -- dominado por el full-build de
   `int_clientes_mapeo_limpio` en el schema `intermediate`, nuevo).
   Confirma de una sola vez: el fix del seed `productos_excluidos`
   (causa raíz, ver "Bugs encontrados"), la restructuración de schemas
   (ver "Decisiones de arquitectura"), y el `contract` de
   `stg_ventas`/`stg_productos` -- ningún error de contract, indicio
   fuerte (no 100% concluyente todavía, ver punto 2) de que
   `dbt-sqlserver` sí lo soporta sobre `view`. No hizo falta correr
   `productos_excluidos --full-refresh` aparte: al ser schema nuevo
   (`seeds`), dbt lo creó de cero con el tipo correcto directamente.
1. **En curso: reconstrucción completa del proyecto contra los schemas
   nuevos** (en vez de seguir persiguiendo un objeto faltante a la vez --
   cada modelo/seed que no fue tocado por una corrida posterior a la
   restructuración de schemas "no existe" en su ubicación nueva, aunque
   sí exista en el `dbt_dev` viejo; ya pasó con `productos_excluidos`,
   `dim_sucursal_mapeo`, `stg_clientes_limpio`/`int_clientes_limpio`).
   Ya confirmado en el camino: `fct_ventas_36m` (PASS, 116s). En curso:
   `+stg_clientes_limpio`. Próximo paso, un solo `dbt build` sin
   selector -- construye todo lo que falta (resto de Canibalización,
   Mayoristas por primera vez contra la base real, y los 2 snapshots SCD2
   al final) en el orden correcto, sin repetir lo pesado (los
   incrementales ya construidos -- `int_clientes_mapeo_limpio`,
   `fct_ventas_36m` -- solo procesan su ventana de lookback, no todo de
   nuevo):
   ```
   dbt build
   ```
   **Incluye el cambio de `fct_ventas_36m` migrado a
   `ref('int_ventas_elegibles')`** (ver Fase 3 abajo) -- primera corrida
   real con esa regla nueva aplicada (exclusión de
   `productos_excluidos` también en Canibalización).
2. **Probar si `dbt-sqlserver` valida contracts sobre `view` de verdad**
   (todavía no descartado que lo esté ignorando en silencio pese al PASS
   de arriba): cambiar a propósito un `data_type` en
   `models/staging/_staging__schema.yml` a algo incorrecto, correr
   `dbt build --select stg_ventas`, confirmar que falla con un error de
   contract, y revertir el cambio de prueba.
3. **Limpieza pendiente, no bloqueante**: los objetos viejos en el
   schema `dbt_dev` (staging/marts previos, construidos antes de la
   restructuración de schemas) quedan huérfanos -- dbt no los borra solo
   al cambiar `+schema`. Revisar con
   `SELECT * FROM sys.schemas WHERE name = 'dbt_dev'` +
   `sys.tables`/`sys.views` de ese schema antes de tirarlos a mano.
4. **Correr los snapshots SCD2 por primera vez** (después de que
   `dim_cliente_tipo_migracion`/`dim_clientes_mayoristas` ya estén
   construidos con datos frescos):
   ```
   dbt snapshot --select dim_cliente_tipo_migracion_snapshot dim_clientes_mayoristas_snapshot
   ```
   La primera corrida inserta todo como versión 1 (`dbt_valid_from` =
   ahora, `dbt_valid_to` = NULL) -- no hay "historia" para ver todavía,
   eso se acumula recién desde la segunda corrida en que algo cambie. Ver
   "Decisiones de arquitectura" abajo para el diseño de cada snapshot.
   También primer uso de `dbt snapshot` en el proyecto -- mismo riesgo de
   adaptador comunitario que los contracts, sin confirmar todavía.
5. Entorno: `cd dbt_ahorrazo && source activar.sh` antes de cualquier
   comando dbt (activa venv Python 3.12, carga `.env`, apunta
   `DBT_PROFILES_DIR` a esta carpeta). Ver `COMANDOS.md` para la
   referencia completa de comandos y selectors.
6. **Convención de esta sesión**: decir qué comando correr, no correrlo
   uno mismo salvo que se pida explícitamente -- el usuario quiere
   ejecutar y entender cada paso.
7. **No mencionar IA/Claude en mensajes de commit** -- preferencia
   explícita del usuario.

---

## Fase 1 — Fundación — CONFIRMADA contra la base real
`stg_ventas`, `stg_productos`, `stg_clientes_mapeo`, `stg_clientes_limpio`,
`stg_clientes`, `fct_ventas_36m`, seed `dim_sucursal_mapeo`. `dbt debug`
funciona (requirió `trust_cert: true` en el profile -- el server usa
certificado autofirmado, hallazgo nuevo no documentado en el plan
maestro original).

## Fase 2 — `clientes_mapeo_limpio` — CONFIRMADA Y REPUNTADA

- [x] `int_clientes_normalizados`, `int_clientes_mapeo_limpio`
  (incremental), `int_clientes_limpio` (`table`) -- construidos y
  testeados contra la base real (`dbt build ... --full-refresh`, 10/10
  PASS, incluye `assert_cliente_id_limpio_no_explota`).
- [x] Perfilado de calidad real corrido (`analyses/perfilar_calidad_cliente_id.sql`):
  800.930 ids totales, 19 con caracteres no contemplados, 32 que
  quedaban vacíos tras limpiar. **Ambos casos ya se investigaron y se
  corrigieron** (ver "Bugs encontrados y corregidos" abajo).
- [x] **`analyses/validar_clientes_mapeo_limpio.sql` -- CORRIDO.**
  Resultado: `total_filas_comparadas=801160`, `conteo_solo_legacy=267`,
  `conteo_solo_nuevo=5985`, `conteo_valor_distinto=16`.
  **`conteo_solo_nuevo` explicado y aceptado, no es un bug**: confirmado
  con el usuario que `dbo.clientes_mapeo` (legacy) hace **meses que no
  se ejecuta** -- los 5985 son clientes reales que se acumularon durante
  ese atraso, invisibles para el legacy pero presentes en la base viva
  contra la que corre el modelo nuevo. Es, literalmente, el problema que
  esta migración resuelve (proceso tan pesado/riesgoso de correr que
  dejó de ejecutarse). `conteo_solo_legacy`/`conteo_valor_distinto`
  quedan dentro del orden de magnitud esperado por los patrones ya
  identificados (no se investigó cada uno al detalle, dado el tamaño
  chico relativo y la urgencia de tiempo).
- [x] **`stg_clientes_mapeo` y `stg_clientes_limpio` repuntados**: ya
  usan `ref('int_clientes_mapeo_limpio')`/`ref('int_clientes_limpio')`
  en vez de `source('dato_solutions', 'clientes_mapeo'/'clientes_limpio')`.
  **Efecto en cadena, sin reconstruir todavía**: todo lo que depende de
  `stg_clientes_mapeo`/`stg_clientes_limpio` (`fct_ventas_36m`,
  `int_ventas_elegibles` y todo lo que cuelga de ahí -- Top 300) sigue
  con datos de la corrida anterior, construidos contra la fuente vieja
  -- ver "Para retomar ahora mismo" arriba para los comandos.
- Nota de performance real observada: el full-refresh de
  `int_clientes_mapeo_limpio` tardó 47 min la primera corrida y 67 min
  la segunda (mismo código) -- variabilidad de carga del server, no un
  problema del modelo. Corridas incrementales normales deberían ser
  mucho más rápidas (solo escanean la ventana de lookback de 45 días).

## Fase 3 — `int_ventas_elegibles` — CONFIRMADA
Unifica las 3 reglas de exclusión (empresa, categoría, cliente test,
producto excluido -- seed `productos_excluidos.csv`, lista real sacada
de `top_300_productos.ipynb`). `dbt build --select +int_ventas_elegibles`
-- 13/13 PASS.

También en esta capa: **`int_ventas_12m`** (ventana móvil de 12 meses,
COMPARTIDA entre Top 300 y Mayoristas -- ver "Decisiones de arquitectura
tomadas en el camino" abajo).

- [x] `fct_ventas_36m` migrado a `ref('int_ventas_elegibles')` en vez de
  su copia inline de las mismas reglas -- una sola fuente de verdad para
  los 3 proyectos, ya no quedan 2 implementaciones de las reglas de
  exclusión. **CAMBIO DE RESULTADO real, no solo de código**: ahora
  Canibalización también excluye los 13 `producto_id` de
  `productos_excluidos.csv` (ids de test/placeholder) -- antes esa
  exclusión solo corría para Top 300. Confirmado con el usuario antes de
  aplicar. Sin confirmar todavía contra la base real con este cambio --
  parte del rebuild completo en curso (ver "Para retomar ahora mismo").

## Fase 4 — Marts por proyecto

### Canibalización — CONFIRMADA con datos de antes del repunte de clientes -- FALTA RE-CONFIRMAR
- [x] `fct_ventas_36m` -- confirmado con el fix de meses cerrados
  (`dbt build --select fct_ventas_36m --full-refresh`, OK), PERO esa
  corrida todavía leía `stg_clientes_mapeo` desde el `source()` legacy
  (sin repuntar). Falta re-correr con la fuente nueva -- ver "Para
  retomar ahora mismo".
- [x] `fct_ventas_36m_pivotado` -- construido y testeado.
- [x] `dim_cliente_tipo_migracion` -- construido y testeado (8/8 PASS,
  incluye `accepted_values` con los 16 `tipo_cliente` reales).
  **DECISIÓN QUE NECESITA CONFIRMACIÓN DE NEGOCIO ANTES DE FASE 6**:
  el legacy (`_conditions()` en `canibalizacion_v1_usado.ipynb`) tiene
  un bug real -- la categoría "Cliente SL, R1 y R2" chequea
  `R1_acumulado` dos veces y nunca `SL_acumulado`, así que cualquier
  cliente con actividad en R1+R2 (sin SL) queda mal etiquetado como
  "SL, R1 y R2" en vez de "Dual R1 y R2" (evidencia: en el
  `value_counts()` real del notebook, "SL, R1 y R2" = 463.626 casos vs.
  "Dual R1 y R2" = apenas 1.302 -- desproporción que cuadra con el bug).
  Se portó la versión CORREGIDA. Efecto: al comparar contra el legacy,
  NO va a coincidir 1:1 en esas dos categorías puntuales (sí debería
  coincidir la suma de ambas).
  **CONFIRMADO CON EL USUARIO -- luz verde para corregir.** El fix ya se
  aplicó también en los 3 lugares del legacy donde aparecía el mismo bug
  (`canibalizacion_v1_usado.ipynb` -- el que corre en producción vía
  `papermill`, `canibalizacion_v1.py`, `etl copy.ipynb`) -- solo código,
  **no se ejecutó ninguno** todavía, así que la tabla de producción
  (`dbo.analisis_sucursales`) sigue con los números viejos hasta que se
  decida correr el notebook corregido (manual o vía el DAG de Airflow).
- [ ] **`canibalizacion_v3.ipynb`** (mismo repo) -- metodología DISTINTA
  a v1, no una corrección del mismo bug: clasifica eventos de migración
  cliente→sucursal con ventana de 24 meses (Nuevo/Recurrente/Ocasional,
  Dual vs. Migración según >3 meses sin comprar en el origen). Completo
  y corrido contra datos reales (4.204.051 filas -> 379.236 eventos ->
  362 filas de salida), ya usa el patrón seguro de escritura
  (`engine_sqlalchemy_bd()`). Escribe a `dbo.canibalizacion_sucursales`
  (tabla resumen agregada, sin `cliente_id`, distinta de v1). **NO
  portado a dbt** -- candidato a una futura fase, no evaluado todavía si
  reemplaza, complementa, o es una vía paralela a
  v1/`dim_cliente_tipo_migracion`.
  - [x] **Duda de diseño confirmada con quien armó la lógica**: el
    usuario diseñó esta parte -- `Local_Origen` fijo (siempre la primera
    sucursal, no la inmediatamente anterior) es intencional para algunos
    usos, pero no sirve para un Sankey/flujo de migración en PowerBI.
    Documentado en el notebook (celda markdown nueva, después del loop
    de clasificación) el cambio de una línea (`local_origen =
    local_destino`) para agregar `Local_Origen_Inmediato` como columna
    NUEVA sin tocar `Local_Origen` -- **no aplicado todavía**, decisión
    de negocio pendiente sobre si hace falta.
  - [x] **Tabla nueva agregada**: `dbo.canibalizacion_evolutivo_cliente`
    -- grano cliente×mes×sucursal (el `df_largo` que antes se
    descartaba), TODOS los clientes de la ventana (~3M filas), para el
    visual de PowerBI del evolutivo mensual por cliente. Tabla aparte,
    no reemplaza `dbo.canibalizacion_sucursales`. Código listo en el
    notebook (sección 13) y en `canibalizacion_v3.py` -- **sin correr
    todavía**.
  - [x] **`canibalizacion_v3.py`** creado -- espejo en texto plano del
    notebook completo (mismo patrón que `canibalizacion_v1.py`), con
    toda la documentación de reglas de negocio y el mapeo pandas→SQL
    incluidos como comentarios/docstring. No se ejecuta solo (no hay DAG
    que lo invoque todavía).

### Top 300 — CÓDIGO LISTO, FIXES SIN CONFIRMAR CONTRA LA BASE (más el repunte de clientes)
- [x] `int_top300_kpis` + `top300_ranking` -- lógica leída del notebook
  real (`ranking_metricas_2025`, `construir_top300_con_metricas`,
  `_normalizar_logaritmica_0_100`): KPIs, normalización log 0-100 (pesos
  0.40/0.30/0.20/0.10, umbral 5.000.000 Gs -- ya en `dbt_project.yml`),
  buckets de unidades por ticket.
- [x] Corregido error 4109 (SQL Server no permite `OVER()` anidado
  dentro de otro `OVER()`) -- normalización separada en etapas explícitas.
- [x] Extraído `int_ventas_12m` compartido (ver abajo) en vez de que Top
  300 calculara su propia ventana.
- [x] Corregido error 245/248, intento 1 (`producto_id` no es puramente
  numérico en la base real -- valores como `"1685-G"` que desbordan
  `int`). `producto_id` casteado a `varchar(100)` en
  `stg_ventas`/`stg_productos`, seed `productos_excluidos` forzado a
  `varchar(50)` vía `column_types`.
- [x] Mismo error 245/248 reapareció con OTRO valor (`"ICN9695"`)
  después del fix de arriba -- confirmado que toda la cadena de arriba
  ya casteaba bien, pero `top300_ranking.sql` seguía fallando en sus 2
  JOIN propios (contra `top300` y `buckets`). Se resolvió forzando
  `cast(producto_id as varchar(100))` explícito en la condición de esos
  2 JOIN, sin depender de que SQL Server propague el tipo solo a través
  de varias vistas anidadas.
- [ ] **Pendiente confirmar de punta a punta**: no se corrió todavía
  `dbt build --select +top300_ranking` con TODOS los fixes aplicados A
  LA VEZ (tipos + `stg_clientes_mapeo` repuntado) -- ver "Para retomar
  ahora mismo" arriba.
- [ ] Pendiente, no bloqueante: enriquecer con metadata de producto
  (nombre/categoria/precio desde `dbo.Productos`) -- el notebook lo hace
  en una celda aparte al final, no portado todavía.

### Mayoristas — CÓDIGO ESCRITO, SIN CORRER TODAVÍA
- [x] Lógica leída del notebook real `analisis_mayoristas_v2.ipynb`
  (`calcular_umbral_ticket_grande`, `calcular_metricas`,
  `clasificar_nivel`) -- 3 modelos nuevos en `models/marts/mayoristas/`:
  `int_mayoristas_umbral_ticket_grande` (Q3+1.5*IQR global, único),
  `int_mayoristas_metricas_cliente` (grano ambito/cliente, GLOBAL+SL+R1+R2),
  `dim_clientes_mayoristas` (puntaje 0-3, `nivel_mayorista`, umbrales Q3
  dinámicos por ámbito vía `PERCENTILE_CONT`).
- **Desvío del plan original**: `clasificar_nivel()` se portó COMPLETO a
  SQL (el plan preveía dejarlo en Python) -- mismo cálculo, mismos
  umbrales, no cambia ningún resultado, solo dónde corre. Ver
  `models/marts/mayoristas/README.md` para el detalle.
- [x] Las exclusiones propias del notebook (`EXCLUIR_CLIENTES`,
  `EXCLUIR_PRODUCTOS` -- mismos 13 ids que Top 300) ya están cubiertas
  por `int_ventas_12m`, no se duplicaron.
- [ ] **Sin correr todavía contra la base real** -- primera vez que se
  prueba `PERCENTILE_CONT`/`CROSS JOIN` en este proyecto, no hay
  garantía de que compile/corra sin ajustes en el primer intento.
  Probar con: `dbt build --select +dim_clientes_mayoristas`.
- [ ] Pendiente, fuera de este repo: portar `clasificar_nivel()` original
  (ahora redundante si el SQL de acá se valida) o simplemente decomisionar
  esa parte del notebook en `analisis_mayorista` durante Fase 6.
- **Confirmado con el usuario**: `analisis_mayoristas_usado.ipynb` (el
  que corre hoy en producción) es la lógica **v1** (ML: `KMeans`,
  `IsolationForest`, `mayorista_score` con umbral fijo 70), NO una
  variante de v2 -- escribe a `dbo.clientes_mayoristas` (sin sufijo).
  `analisis_mayoristas_v2.ipynb` (la que se portó acá) escribe a
  `dbo.clientes_mayoristas_v2`. **Decisión pendiente para Fase 6**: a
  cuál de los dos nombres apunta finalmente `dim_clientes_mayoristas`
  -- probablemente `clientes_mayoristas` (sin sufijo), ya que es el que
  en producción hoy probablemente leen dashboards/otros consumidores,
  pero hay que confirmar el mapeo de consumidores antes de decidir
  (mismo paso que ya se documentó como obligatorio en el plan maestro
  antes de cualquier cutover).
- **Trabajo hecho FUERA de este repo, en `analisis_mayorista` (repo
  separado, commit `3f956fb`)**: se reescribieron `analisis_mayoristas.py`
  (ahora sí espejo fiel de `usado.ipynb`/v1 -- el archivo viejo agrupaba
  por `cliente_id` crudo, no `cliente_id_limpio`, un bug real que
  perdía la deduplicación) y se agregó `analisis_mayoristas_v2.py`
  (espejo del notebook v2, portado acá a `dim_clientes_mayoristas`).
  También se agregó `engine_sqlalchemy_bd()`/`escribir_tabla_segura()`
  a `conexion_bd.py` de ese repo (no existía motor de escritura seguro
  ahí -- mismo patrón que ya tenían `canibalizacion_ahorrazo`/`top_300_productos`).
  Ninguno de los dos scripts nuevos escribe a SQL por default (flag
  `--escribir-sql` explícito) -- no se tocó la tabla de producción.

---

## Bugs encontrados y corregidos durante la migración (no en el plan original)

1. **`clientes_mapeo_limpio.sql` (legacy)**: prometía en un comentario
   "quita el caracter '|'" pero el código nunca lo hacía. Corregido de
   forma general (no solo para `|`): cualquier símbolo suelto al
   principio/final de un id se saca (`recortar_basura_extremos`, nuevo
   macro), y cualquier símbolo no numérico seguido de un solo dígito al
   final (ej. `"3891542,1"`, `"2546408_6"`, `"881511/9"`) se trata como
   separador de RUC igual que `-`/`*` (extensión de
   `derivar_cliente_id_limpio`).
2. **Clientes no identificables**: ids que son puro texto (nombres de
   persona cargados por error, ej. `"ABRAHAM"`, `"SIN NOMBRE"`) quedaban
   vacíos tras la limpieza y el legacy caía a usar el id original como
   si fuera válido -- mezclando clientes distintos que comparten el
   mismo nombre/placeholder. Decisión del usuario: excluirlos de la
   segmentación (`cliente_id_limpio` = NULL, filtrado explícito en
   `int_clientes_mapeo_limpio`/`int_clientes_limpio`), no inventarles un
   id.
3. **`_conditions()` (canibalización, notebook)**: ver Fase 4
   Canibalización arriba -- bug de `R1_acumulado` chequeado dos veces.
4. **Ventanas móviles no eran de meses cerrados**: `int_ventas_12m` y
   `fct_ventas_36m` usaban `GETDATE()` directo como límite superior,
   mezclando el mes en curso (parcial) con meses ya cerrados. El
   legacy (`view_ventas_ahorrazo_filtradas_12m`) ya lo resolvía bien
   con un CTE "limites" -- se portó ese mismo criterio vía el nuevo
   macro `fecha_corte_mes_cerrado()`.
5. **`producto_id` no es puramente numérico**: ver Top 300 arriba (2
   intentos -- el cast en staging/seed no alcanzó, hizo falta forzar el
   cast también en los JOIN de `top300_ranking.sql`).
6. **Mismo bug de `producto_id`, tercera aparición -- causa raíz real
   encontrada esta vez**: el seed `productos_excluidos` (creado en el
   commit `d8e2528`) quedó con `producto_id` inferido como `int` porque
   en ese momento no existía el `+column_types` que lo fuerza a
   `varchar(50)` (agregado después, en `53a65b0`). `dbt seed`/`dbt build`
   sin `--full-refresh` hacen `TRUNCATE`+`INSERT` sobre la tabla que ya
   existe -- **nunca vuelven a aplicar `column_types`**, eso solo pasa en
   un `CREATE` nuevo. La tabla física quedó en `int` todo este tiempo,
   invisible leyendo el código del proyecto. El `LEFT JOIN` contra ella en
   `int_ventas_elegibles.sql` forzaba a SQL Server a convertir
   `v.producto_id` (varchar, con valores reales no numéricos) a `int` por
   precedencia de tipos -- eso rompía, con un valor distinto cada vez
   según el plan de ejecución de esa corrida puntual. Fix: `--full-refresh`
   del seed (recrea la tabla con el tipo correcto) + cast explícito
   forzado también en los 2 JOIN de `int_ventas_elegibles.sql` (mismo
   patrón defensivo que ya tenía `top300_ranking.sql`, para que un futuro
   schema drift similar no vuelva a explotar en silencio).
   **Regla a seguir de acá en más**: si se cambia `column_types` de un
   seed que ya existe en la base, correrlo con `--full-refresh` -- si no,
   el cambio se ignora sin ningún aviso.

## Decisiones de arquitectura tomadas en el camino (no estaban en el plan original)

- **`int_ventas_12m`** (`models/intermediate/`): el plan original tenía
  a Top 300 y Mayoristas calculando su propia ventana de 12 meses por
  separado. Se detectó la duplicación (el legacy ya comparte
  exactamente esta ventana entre los 2 vía
  `view_ventas_ahorrazo_filtradas_12m`) y se extrajo a un solo modelo
  compartido en `intermediate/`.
- **Entorno de desarrollo local, no WSL todavía**: el plan original
  asumía dbt instalado directo en WSL (junto con Airflow). Para
  iterar rápido se armó un entorno local (Windows, Git Bash, Python
  3.12 venv) conectado por VPN al server -- `profiles.yml`/`.env` viven
  en la raíz del repo (gitignorados) en vez de `~/.dbt/`, con
  `DBT_PROFILES_DIR` apuntando ahí (`activar.sh` automatiza esto). Ver
  `README.md` ("Setup local"). Migrar esto a WSL/Airflow sigue siendo
  Fase 5, no se tocó todavía.
- **`contract: enforced: true` en `stg_ventas`/`stg_productos`**: declara
  el tipo de cada columna explícitamente (`producto_id varchar(100)`,
  etc. -- tipos reales confirmados contra `INFORMATION_SCHEMA` de
  `dbo.Ventas_Ahorrazo`/`dbo.productos`). Si el tipo real cambia en la
  fuente, o alguien saca un cast sin querer en el futuro, dbt falla acá
  mismo con un mensaje claro, en vez de que aparezca como un error de
  conversión río abajo en algún mart (la clase de bug de `producto_id`
  que motivó esto). **Sin confirmar todavía**: si `dbt-sqlserver`
  (adaptador comunitario) soporta contracts sobre modelos `view`
  correctamente -- primera vez que se usa esta feature en el proyecto.
  Si el build tira error de tipo no soportado o un mismatch en
  `categoria_1`/`categoria_2` (`varchar(max)`, la forma en que se
  declaró acá puede no coincidir exacto con cómo lo reporta el
  adaptador), ajustar el `data_type` del schema.yml al que indique el
  mensaje de error de dbt.
- **SCD2 vía `dbt snapshot` sobre `dim_cliente_tipo_migracion` y
  `dim_clientes_mayoristas`** (`snapshots/*.sql`) -- mecanismo estándar de
  dbt para esto, no lógica de MERGE escrita a mano. `strategy='check'`
  en los dos (no `timestamp`: son tablas derivadas, sin `updated_at` de
  origen).
  - `dim_cliente_tipo_migracion_snapshot`: el modelo YA tiene grano
    mensual, esto no agrega historia nueva -- preserva qué
    `tipo_cliente` se reportó en cada corrida, porque el acumulado
    corrido (`SUM() OVER (... ROWS UNBOUNDED PRECEDING)`) puede
    recalcular clasificaciones pasadas distinto si llega una venta
    tarde. `invalidate_hard_deletes=False`: que un (cliente, mes)
    desaparezca no es un evento de negocio, es solo la ventana rolling
    de 36 meses de `fct_ventas_36m` -- no hay que cerrar esa versión.
  - `dim_clientes_mayoristas_snapshot`: caso más directo -- el modelo NO
    tenía dimensión de tiempo (grano `ambito, cliente_id_limpio`, estado
    único). `check_cols` limitado a `nivel_mayorista`/`puntaje` a
    propósito -- las métricas continuas (umbrales, ventas) fluctúan de
    corrida en corrida sin que cambie la clasificación de negocio,
    versionar por eso sería ruido. `invalidate_hard_deletes=True` (al
    revés que el otro): que un cliente desaparezca acá SÍ es una señal
    real -- dejó de calificar para cualquier nivel.
  - **Cuidado operativo de acá en más**: `dbt snapshot --full-refresh`
    borra TODA la historia acumulada de un snapshot -- tratarlo como
    comando peligroso, no como un `--full-refresh` cualquiera de un
    modelo normal.
- **Desempate determinístico en `top300_ranking`**: `row_number()` para
  la posición del ranking solo ordenaba por `puntaje_final desc, ventas
  desc` -- si dos productos empataban en ambos, SQL Server no garantiza
  el mismo orden entre corridas (rompe idempotencia: la posición #300
  podría "parpadear" sin que cambie ningún dato real). Se agregó
  `producto_id` como tercer criterio de desempate.
- **Un schema de base de datos por capa/proyecto, no todo en `dbt_dev`**:
  `staging`, `intermediate`, `marts_canibalizacion`, `marts_top_300`,
  `marts_mayoristas`, `seeds` -- configurado vía `+schema` en
  `dbt_project.yml`. Nombres limpios, SIN prefijo de entorno (dbt por
  default concatena `target.schema` + el nombre custom, ej.
  `dbt_dev_staging`) -- se sobreescribió `generate_schema_name` en
  `macros/generate_schema_name.sql` para usar el nombre tal cual.
  Decisión explícita: dev y prod comparten la misma base (limitación del
  cliente, aclarada desde el inicio del proyecto), así que el prefijo de
  entorno no daba aislamiento real, solo ruido en los nombres.
  **Efecto colateral a tener en cuenta**: el target `prod` que ya existe
  en `profiles.yml` (schema `dbo`, comentado como "NO usar hasta Fase 6")
  queda parcialmente obsoleto con este cambio -- al ignorar
  `target.schema`, correr `dbt build -t prod` escribiría en los MISMOS
  nombres de schema que `dev` (`staging`, `marts_top_300`, etc.), no en
  `dbo`. En la práctica no hay hoy una separación real entre "dev" y
  "prod" a nivel de dbt: lo que se construye en `dev` ES lo que
  eventualmente se convierte en producción -- no hay una segunda copia
  paralela. **Decisión pendiente para Fase 6**: redefinir qué sentido
  tiene (si alguno) mantener un target `prod` separado, dado este
  esquema -- probablemente alcance con seguir usando `dev` hasta el
  corte, en vez de mantener dos targets que ya no representan entornos
  distintos.
