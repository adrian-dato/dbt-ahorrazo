# Pendientes

Lo que queda abierto en `dbt_ahorrazo` y en lo que depende de él. Los diagramas de
dependencias y el orden de ejecución están en `ARQUITECTURA.md`; los comandos, en
`COMANDOS.md`.

---

## La fuente de ventas pasó a `Ventas_pos`

Desde el 20/10/2026 el cliente actualiza `dbo.Ventas_pos` y deja de actualizar
`dbo.Ventas_Ahorrazo`, que quedó deprecada. El código ya lee la tabla nueva: el
modelo `stg_ventas`, el test de frescura y la declaración de la fuente. Es el único
punto de contacto con la tabla, así que todo lo demás se enteró sin tocarse.

El cliente dijo que tiene la misma estructura y granularidad, pero no se verificó.
El contrato de `stg_ventas` hace fallar el build si algún tipo de columna es
distinto, y no detecta lo importante: si trae el historial completo o si los datos
coinciden con los de la tabla anterior. Eso lo comprueba
`analyses/verificar_cambio_a_ventas_pos.sql`, que hay que correr antes de reconstruir
nada. Según el resultado:

- Si la estructura y los totales mes a mes coinciden y el historial llega hasta donde
  llegaba el de la tabla anterior, no hay más cambios. Si los totales de algún mes
  cerrado difieren, los dos modelos incrementales (`int_clientes_mapeo_limpio` y
  `fct_ventas_36m`) arrastran datos de la tabla anterior y hay que reconstruirlos con
  `--full-refresh`.
- Si `Ventas_pos` arranca más tarde, no alcanza como fuente única: las ventanas de 12,
  24 y 36 meses quedarían cortas. `stg_ventas` tendría que unir las dos tablas con una
  fecha de corte, y conviene que el cliente confirme desde cuándo es cada una.
- Si el formato de `timbrado` o `factura_nro` cambió, una factura presente en las dos
  tablas se contaría dos veces al unirlas.

La primera corrida ya mostró que no es del todo la misma estructura: `fecha_venta`
llega como `datetime2(6)`, con hora, y la tabla anterior la traía como `date`. El
contrato de `stg_ventas` frenó el build, y se resolvió pasándola a `date` en esa vista.
Era importante: las visitas de Mayoristas, los días con venta de Top 300 y la venta
diaria cuentan días distintos de esa columna, y con la hora incluida cada venta habría
contado como un día. Queda por comprobar que la hora sea la de Paraguay y no UTC, porque
si fuera UTC una venta de la noche caería en el día siguiente; es la consulta 6 de
`analyses/verificar_cambio_a_ventas_pos.sql`. Y como la tabla nueva sí trae la hora, es
información que la anterior no tenía y que hoy se descarta.

La verificación del 20/10/2026 mostró que `Ventas_pos` no reemplaza a la tabla anterior
sin cambios:

- **Historial.** Va del 17/08/2024 al 18/10/2026, con 180,8 millones de filas; la anterior
  iba del 30/09/2018 al 06/08/2026, con 263,1 millones. Las ventanas de 12 y de 24 meses
  entran enteras, la de 36 no: faltan unos diez meses (octubre de 2023 a mediados de agosto
  de 2024) para Canibalización y para la venta diaria por categoría.
- **Puntos de venta.** Trae cinco (1, 2, 3, 5 y 6) y la anterior tres (3, 5 y 6). Los puntos 1
  y 2 suman 31,4 millones de filas, el 17% de la tabla, y no se sabe qué son. En los meses que
  están en las dos tablas, de octubre de 2024 a julio de 2026, la nueva tiene entre 24% y 37%
  más filas (mediana 31%) y entre 16% y 28% más venta (mediana 23%), sin contar agosto y
  septiembre de 2025. Los puntos 1 y 2 aportan unas 1,2 millones de filas por mes de las 1,65
  millones de diferencia, o sea cerca de tres cuartos; el resto no está explicado. En julio
  de 2026 trae 172.014 clientes contra 138.652 y 52.012 productos contra 40.469, con casi las
  mismas líneas por factura (11,6 contra 11,9), lo que habla de más facturas y no de líneas
  duplicadas.
- **Columnas nuevas.** `id_empresa`, `PRIMARIO` y `fecha_detalle`. Si `id_empresa` distingue
  a qué empresa pertenece cada punto de venta, filtrarla alinearía la tabla nueva con la
  anterior; hay que mirarlo.
- **La fecha.** `fecha_venta` trae hora, y se pasa a `date` en `stg_ventas`. Falta comprobar
  que la hora sea la de Paraguay (consulta 6 del analysis de verificación).
- **Calidad del dato, en las dos tablas.** En agosto y septiembre de 2024 la venta por
  línea es unas cuatro veces la de los meses vecinos (unos 46.000 Gs por línea contra 10.600)
  y las unidades por línea, seis contra 1,5, con las filas apenas un 45% más altas. Pasa igual
  en las dos tablas, así que viene del origen, y esos dos meses caen dentro de la ventana de
  36 meses. En agosto de 2025 la tabla anterior tiene 8,8 millones de filas contra unos 5,4
  millones de un mes normal, unos 3,4 millones de más, que parece una carga doble; la tabla
  nueva tiene ese mes en 7,5 millones, normal. Por eso la diferencia entre las dos da al
  revés en agosto de 2025 (la nueva, 15% menos) y casi se anula en septiembre.
- **`medio_pago`.** La anterior tiene errores de codificación (`Tarjeta de cr+®dito`, 4,1
  millones de filas); la nueva no los tiene, pero suma valores nuevos como `A verificar` y una
  `Transferencia Bancaria` bien escrita junto a la `Tranferencia` con error.

También falta saber si `Ventas_pos` es un heap o tiene columnstore: la anterior, en
el último relevamiento, era un heap sin índice. Las cifras de volumen de la
documentación (238 millones de filas) son de la tabla anterior.

Los scripts y notebooks anteriores a dbt, en `scripts-sql-ahorrazo` y en los notebooks
viejos de `analisis_mayorista` y `top_300_productos`, siguen leyendo la tabla
deprecada. Son historia y no se corren, pero no se actualizaron. Cuando
`Ventas_Ahorrazo` se dé de baja, el analysis de verificación se elimina.

## Después de reconstruir Mayoristas

Cada vez que corre el DAG mensual del día 1, tres cosas dependen de los números:

- Releer los cortes con la sección 2 de `analyses/metodologia_mayoristas_v3.sql`,
  actualizar las constantes de
  `analisis_mayorista/tablero_powerbi/diagramas/generar_diagramas.py` y volver a
  generar los diagramas.
- Actualizar el reparto por nivel en `prompt_presentacion_mayoristas.txt`.
- Refrescar el informe de Power BI, y en la consulta de `Clientes` marcar las columnas
  nuevas, como `facturas`, que no aparecen solas.

Si `mayoristas_v3_tickets_unidad` sigue siendo una tabla en la base, hay que borrarla
antes del build, porque el modelo pasó de tabla a vista y dbt no siempre hace esa
conversión de forma limpia:

```sql
drop table if exists marts_mayoristas.mayoristas_v3_tickets_unidad;
```

## Limpieza de objetos en la base

`scripts/mantenimiento/limpiar_objetos_mayoristas_v2.sql` tiene los `DROP` de lo que
quedó sin administrar después del cutover: los tres modelos de la versión anterior, el
mart de canasta y la tabla que escribía el notebook por pandas. Está listo para
correr. En la misma carpeta, `baja_vista_int_ventas_12m.sql` da de baja la vista
`intermediate.int_ventas_12m` y `baja_vistas_staging_de_clientes.sql` las dos vistas
de staging que envolvían al mapeo y a la dimensión de clientes. Las tres cosas se
eliminaron del repo y los dos scripts van después de desplegar el código nuevo en el
servidor.

Dos quedaron comentados a propósito, `dbo.clientes_mayoristas_v2` y
`dbo.clientes_mayoristas`. El segundo tiene 952.012 filas de febrero y es la tabla que
leía producción antes de dbt. Las dependencias dentro de SQL Server dieron vacío, pero
eso no cubre un archivo de Power BI, un Excel con conexión o un notebook. Hay que
confirmarlo antes de descomentar.

Falta también revisar si existe el snapshot de la versión anterior en el schema
`snapshots`. La consulta está al final de ese mismo archivo.

## Historia de la clasificación

Al eliminar la versión anterior salió con ella su snapshot SCD2, que era el único
registro de cómo cambiaba la clasificación mes a mes. Ahora hay uno nuevo,
`mayoristas_v3_resumen_snapshot`, que corre en el DAG mensual después de construir
Mayoristas. La historia empieza con su primera corrida; lo anterior no se puede
reconstruir.

Dos cosas para tener presentes al leerla. Los cortes se movieron hasta hace poco (el
de Pack se tocó el 01/09 y el 15/09, ver el comentario en
`int_mayoristas_v3_umbral_ticket.sql`), y un cambio de corte mueve de nivel a muchos
clientes a la vez sin que haya cambiado su forma de comprar. Y como la ventana sigue el
calendario aunque el cliente no actualice la fuente, los clientes cuyas compras caen
fuera de lo cargado salen de la clasificación y cierran su versión. Si un mes de la
historia muestra un salto raro, esas son las dos primeras explicaciones.

## Canibalización corre dos versiones a la vez

`models/marts/canibalizacion/` tiene dos metodologías conviviendo. La v1 es
`dim_cliente_tipo_migracion`, portada de `canibalizacion_v1_usado.ipynb`. La v3 son
cuatro modelos portados de `canibalizacion_v3.py`: `int_canibalizacion_migracion_base`,
`dim_cliente_migracion_eventos`, `fct_canibalizacion_evolutivo_cliente` y
`fct_canibalizacion_migracion_resumen`.

El problema no es que convivan, es cómo se orquestan. El DAG semanal corre
`dbt build --select +dim_cliente_tipo_migracion`, que es la cadena de la v1. Los cuatro
modelos de la v3 no son ancestros de ese modelo, así que ninguna corrida programada los
reconstruye: quedan con la ventana del día en que alguien los corrió a mano. Es lo
mismo que le pasaba a los modelos de mayoristas antes del cutover, y ahí se notó
recién cuando aparecieron 2.224 clientes sin clasificación en el tablero.

Son dos decisiones separadas y conviene no mezclarlas. Cambiar el selector del DAG a
`+tag:canibalizacion` hace que se reconstruyan las dos versiones y no depende de validar
nada: una tabla desactualizada es peor que una tabla que sobra. El cutover de v1 a v3
necesita la validación que esa versión todavía no tuvo.

`fct_ventas_36m` quedó con meses de montos parciales por el lookback de 45 días que
tenía antes de pasar a meses cerrados, y los meses que salían de la ventana no se
borraban. Las dos cosas están corregidas en el código. Falta un `--full-refresh` de
ese modelo, una sola vez, para reparar lo que ya estaba cargado, y volver a construir
lo que depende de él.

## Categorías de producto

`dim_categoria`, `dim_cliente` y `fct_ventas_diarias_categoria_36m`, en `marts_core`, las
construyen el DAG semanal y el mensual con `tag:core`. La primera vez hay que
construirlas a mano, con la capa base y Mayoristas ya hechos, antes de desplegar los
DAGs: el DAG semanal corre un test que necesita la venta diaria. `dim_categoria` queda
desactualizada hasta la próxima corrida cuando el catálogo gana categorías nuevas.

Los análisis que pidió el cliente después de entregar el de mayoristas (qué productos
están en baja, si un producto reemplaza a otro, por qué bajan los panificados de
fábrica) parten de estas tablas y de `int_ventas_24m_tabla`. No están construidos.

## Productos sin ficha en el catálogo

Es la exclusión más grande del análisis en plata y la única que no responde a una
decisión de negocio. Medido sobre la ventana de septiembre 2025 a agosto 2026:
2.013.785 renglones de venta y 35.405 millones de guaraníes, el 4,8% de la venta del
período, de artículos que no figuran en el maestro de productos. Afectan a 232.819
clientes, seis de cada diez.

Sin ficha no se sabe ni la categoría ni la unidad de medida de esos artículos, así que
no hay forma de clasificarlos. Que estén repartidos entre la mayoría de los clientes
sugiere productos dados de baja del catálogo antes que un problema de cruce, pero eso
no está verificado.

La consulta que los mide es la sección 1 de `analyses/metodologia_mayoristas_v3.sql`.

## Dos cadencias sobre la misma tabla

`int_ventas_12m_tabla` la reconstruyen dos DAGs con frecuencias distintas: el semanal
de Top 300 y el mensual de Mayoristas. El que corre último deja su versión.

Dentro de un mismo mes la ventana no cambia, así que el desfase de período no vuelve a
aparecer. Lo que sí puede entrar es venta de días que ya estaban dentro de la ventana y
llegaron tarde a la fuente. Por eso la consulta que alimenta el informe de Power BI se
acota al rango que tienen las tablas de `marts_mayoristas`.

Si eso llegara a molestar, la salida es alinear las cadencias. Materializar una copia
aparte para mayoristas duplicaría 62 millones de filas para resolver algo que un filtro
de dos líneas ya resuelve.

## Cortes de frecuencia de compra

Los cortes de 10, 20 y 45 días que separan Semanal, Quincenal y Mensual están en
`dbt_project.yml`. No son percentiles del dato: semana, quincena y mes son conceptos
del negocio, y hay que confirmarlos con el área comercial.

## Top 300

El ranking todavía no trae el nombre, la categoría ni el precio de cada producto. El
notebook original lo hacía en una celda al final y esa parte no se portó, así que el
resultado muestra códigos.

## Limpieza de clientes

`int_clientes_normalizados`, `int_clientes_mapeo_limpio` e `int_clientes_limpio` ya
reemplazaron al proceso anterior. La consulta que hizo la comparación contra el
proceso anterior ya cumplió su función y se eliminó, y el resultado quedó documentado en
el comentario de `int_clientes_mapeo_limpio.sql`. Lo mismo pasó con la que comparaba la
regla de `tipo_persona` contra el CASE del proceso anterior.

`analyses/perfilar_calidad_cliente_id.sql` sigue disponible. El perfilado mostró 51
casos raros sobre 800.930 identificadores: 19 con caracteres no contemplados y 32 que
quedan vacíos después de limpiar.

## Credenciales en Airflow

El código de las tareas ya toma las credenciales de la conexión de Airflow
`dbt_ahorrazo_sqlserver`, y usa el `.env` del servidor solo si esa conexión no existe.
Falta crearla en el servidor, comprobar en el log de una corrida que se está usando y
borrar el `.env` de la carpeta del proyecto en el servidor. Los pasos están en el README
de `orquestacion_ahorrazo`. También falta confirmar que Airflow tenga configurada una
`fernet_key`; sin ella no cifra la contraseña.

## Auditoría del proyecto

Resultado de revisar todos los modelos, macros y archivos de soporte. Lo que ya se
resolvió (versiones fijadas, la vista `int_ventas_12m`, el script de bajas fuera de
`analyses/`, los archivos de ejemplo, las credenciales, los comentarios con fases
vencidas, los tests de grano y la capa `marts_core`) no figura acá. Quedan estos
puntos, de mayor a menor riesgo.

**Los entornos de desarrollo y producción no están aislados.** `generate_schema_name`
usa el nombre de schema de cada modelo tal cual, así que un `dbt build` desde una
compu local reescribe las mismas tablas que lee Power BI. Airflow corre dbt sin
`--target`, de modo que usa el `dev`, y el target `prod` apunta a `dbo` y dice que no
se use. La salida es un prefijo de schema para desarrollo (`dev_<usuario>_...`) más
`--defer --state` apuntando al manifest de producción, para no reconstruir las tablas
de 62 millones de filas en cada prueba. Hay que renombrar los targets para que el de
Airflow se llame `prod`.

**No hay integración continua ni linter.** Todo se valida corriendo contra la base
real. `dbt parse` no necesita conexión y alcanza para detectar errores de sintaxis,
Jinja y YAML en cada commit; se puede sumar `sqlfluff`. Las macros de limpieza de
identificadores son funciones puras y buenas candidatas a tests unitarios de dbt.

**`venta_gs` se suma como `float` en los marts existentes.** Una de las decisiones de
más abajo dice que se suma casteada a decimal para que el resultado sea reproducible,
pero solo la aplican los modelos más nuevos. Falta castear una vez en `stg_ventas`, con
el contrato de esa columna como `decimal`, y que todo lo de abajo herede el tipo.

**La capa de entidades compartidas está a medias.** `marts_core` ya tiene la dimensión
de categorías y la venta diaria por categoría. Falta el resto de lo que los tableros
importan hoy desde `intermediate`: la venta por línea, el cliente, el producto y la
sucursal. La venta por línea, de 62 millones de filas, conviene construirla como tabla
en el mart y no como vista, para poder controlar sus índices, y que los marts de
Mayoristas y Top 300 la lean desde ahí. Las dimensiones, que son chicas, pueden ser
tablas finas. Falta declarar `access: public`, el contrato de columnas y `exposures` para
cada tablero, y dar permiso de lectura al usuario de Power BI solo sobre los `marts_*`.
Cuatro modelos `int_` siguen viviendo dentro de `marts/`.

**Los nombres no son uniformes.** `mayoristas_v3_*` conserva `v3` aunque la lógica es la
v4, y unos modelos llevan `fct_` o `dim_` y otros no (`mayoristas_*`, `top300_ranking`).
`dim_cliente_tipo_migracion` tiene una fila por cliente y mes, así que es un hecho.

**Los modelos dependen del reloj.** `fecha_corte_mes_cerrado()` y otros filtros usan
`getdate()`, así que no se puede reconstruir un mes pasado ni probar con una fecha fija.
Una variable `fecha_corte` opcional lo resolvería.

**Los modelos incrementales no tienen salvaguardas.** Sin `on_schema_change`, y nada
impide un `--full-refresh` accidental de un modelo que tarda entre 47 y 67 minutos. Con
`delete+insert` sobre columnstore hay que vigilar la fragmentación.

**Los tests nuevos están en `warn`.** Los de grano, las relaciones y los dos de
conciliación entre capas. Después de una corrida limpia conviene pasarlos a error, y
revisar cuánto tardan los de grano sobre las tablas grandes.

## Documentación

Los cinco documentos de propuesta y plan de reingeniería (`PLAN_MAESTRO_REINGENIERIA.md`
en la raíz, y uno por subproyecto en `scripts-sql-ahorrazo`, `top_300_productos`,
`canibalizacion_ahorrazo` y `analisis_mayorista`) ya se revisaron. Se decidió
conservarlos como historia en vez de darlos de baja: los tres que todavía se
presentaban como propuesta vigente (`analisis_mayorista/PLAN_REINGENIERIA.md`,
`top_300_productos/PROPUESTA_REINGENIERIA.md`, `scripts-sql-ahorrazo/plan_reingenieria.md`)
quedaron marcados con el mismo banner de "documento histórico" que ya tenía
`canibalizacion_ahorrazo/propuesta_reingenieria_pipeline.md`, remitiendo al README
vigente de cada repo. `informe_arquitectura_datos.md`, en la raíz, se marcó igual.
`PLAN_MAESTRO_REINGENIERIA.md` no necesitó el banner: su sección "Estado de ejecución"
ya se mantiene al día.

`canibalizacion_ahorrazo/PENDIENTES.md` tampoco está actualizado -- no se revisó en
detalle qué parte quedó vieja.

---

## Decisiones que conviene no volver a discutir

Están tomadas y documentadas donde corresponde. Se listan acá para no reabrirlas.

**El multiplicador del corte de factura grande es 3 y no 1,5.** El 1,5 es la regla
estándar para marcar un dato atípico. Acá se busca la compra de quien surte un negocio,
y con 1,5 el corte en kilos caería en 16,74 en lugar de 25,92.

**C3 usa el promedio por factura y no la suma del período.** Sumar mezcla a quien gasta
mucho por visita con quien viene muchas veces.

**Blis, Metros y Ramo quedan fuera de C1 y C2.** Casi todas sus facturas llevan una sola
pieza y no hay corte que separe una compra grande de una normal. Entran en C3, que es en
guaraníes. Solo 34 clientes de 384.980 compraron únicamente en esas tres.

**Los percentiles se calculan en consultas separadas por unidad de medida**, no con una
ventana particionada. Esa partición dejó la instancia sin responder dos veces.

**`venta_gs` se suma casteada a decimal.** Es `float` en el contrato de `stg_ventas`, y
sumar floats en paralelo no da el mismo resultado entre corridas.

**La regla de la ventana móvil vive solo en `fecha_corte_mes_cerrado()`.**
`int_ventas_12m_tabla` e `int_ventas_24m_tabla` leen `int_ventas_elegibles` y aplican el
filtro con ese macro: cada una solo decide cuántos meses mira.

**Las ventanas siguen el calendario aunque el cliente no actualice la fuente.** El 1/11
Mayoristas se reconstruye sobre noviembre 2025 a octubre 2026 con los datos que haya, y
no se frena si la fuente está atrasada. El test de frescura avisa por mail, pero no
detiene el build.

**Las entidades que usa más de un proyecto van en `marts_core`.** Es la convención que
sigue el patrón `marts_<área>` del repo y deja claro que están aguas arriba de los marts
de cada proyecto.

**No se usan las versiones de modelos de dbt (`versions:`) por ahora.** Sirven cuando
hay consumidores externos que necesitan migrar a su ritmo. Con un equipo chico y la v4
de Mayoristas ya reemplazando a la v3, se cambia el modelo directamente.
