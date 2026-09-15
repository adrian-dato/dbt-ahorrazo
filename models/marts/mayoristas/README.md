# marts/mayoristas/

Clasifica a cada cliente en un nivel de mayorista, de Alto a Minorista, según
cuánto se parece su forma de comprar a la de alguien que revende.

## La metodología

Tres criterios, un punto cada uno, sobre una ventana móvil de doce meses
cerrados. La suma da el nivel: 3 es Alto, 2 Medio, 1 Potencial y 0 Minorista.

**C1, volumen por visita.** Promedio de unidades por factura, calculado por
separado en cada unidad de medida. Cumple si está en el percentil 75 o más
comparado con el resto de los clientes que compran esa misma unidad. Alcanza con
cumplirlo en una.

**C2, repetición del volumen.** Primero se define a partir de cuántas unidades
una factura es grande, con `Q3 + 3 × IQR` sobre todas las facturas de esa unidad
de medida. Después se mira qué proporción de las facturas del cliente superaron
ese corte. Cumple si al menos el 40% lo superó, o el percentil 75 del resto de
los clientes si ese fuera más alto. También basta con cumplirlo en una unidad.

En Pack, Q1 y Q3 valen 1: tres de cada cuatro facturas llevan un solo pack. Con
IQR cero la fórmula se reduce a Q3 y el corte deja de separar, así que en ese caso
el corte pasa a ser el doble de Q3 en lugar de aplicar `Q3 + 3 × IQR`, y queda en
2. El test `assert_unidades_con_variancia` informa en cada corrida qué unidad de
medida está en esa situación.

**C3, valor por visita.** Venta promedio por factura, no la suma del período:
sumar mezclaría a quien gasta mucho por visita con quien viene muchas veces. Es
global, entran todas las unidades de medida, porque acá todo está en guaraníes.
Cumple si está en el percentil 75 del resto de los clientes.

C1 y C2 se calculan únicamente sobre Unid, KILOS, LITROS y Pack. Blis, Metros y
Ramo quedan afuera porque casi todas sus facturas llevan una sola pieza y no hay
corte que separe una compra grande de una normal. En C3 entran las siete.

Que cada unidad de medida se mida contra su propia vara es el centro de todo. Un
cliente que se lleva 130 kilos de carne y 697 unidades sueltas en la misma
factura no compró 827 de nada.

## La cadena de modelos

```
int_ventas_12m_tabla
  → int_mayoristas_v3_tickets_por_unidad   tabla    cliente × factura × unidad
      → int_mayoristas_v3_umbral_ticket    tabla    4 filas: Q1, Q3, IQR y el corte
          → mayoristas_v3_tickets_unidad   vista    lo anterior con los cortes al lado
              → mayoristas_v3_metricas_unidad   cliente × unidad, con C1 y C2
                  → mayoristas_v3_resumen        cliente, con el puntaje y el nivel
                  → mayoristas_v3_umbrales       referencia de metodología
              → mayoristas_v3_frecuencia_compra  cliente, cada cuánto viene
```

`mayoristas_v3_resumen` lee además `int_ventas_12m_tabla` directo para C3, que
toma todas las unidades de medida y no solo las cuatro con C1 y C2.

### Por qué la cadena está partida así

La cadena está separada en varios modelos para no recorrer las tablas grandes más
veces de las necesarias. Dos de estas decisiones salieron de corridas que dejaron
la base sin responder.

**El cálculo de los cuartiles está en su propio modelo.** En SQL Server una
expresión `WITH` se vuelve a resolver cada vez que se la referencia. Dentro de
`mayoristas_v3_tickets_unidad` se la referenciaba cinco veces, y la agregación de
62 millones de líneas se ejecutaba otras tantas. Con el cálculo en
`int_mayoristas_v3_umbral_ticket`, que devuelve cuatro filas, ese modelo puede ser
una vista.

**Q1 y Q3 salen de cuatro consultas separadas**, una por unidad de medida, en
lugar de una ventana particionada por esa columna. Unid y KILOS concentran más
del 99% de las facturas, así que esa partición reparte el trabajo paralelo de
forma muy desigual.

**`mayoristas_v3_umbrales` toma los cortes de los modelos chicos.** Unir las dos
tablas grandes por `unidad_medida`, que tiene cuatro valores posibles, genera el
producto cartesiano completo antes de que el `GROUP BY` lo reduzca.

## Orquestación

El DAG mensual corre `dbt build --select +tag:mayoristas` el día 1 a las 02:00,
en `orquestacion_ahorrazo`. El tag está puesto a nivel carpeta en
`dbt_project.yml`, así que cualquier modelo nuevo que se agregue acá entra solo.

## Lo que queda de la versión anterior

La v2 se eliminó del repo cuando se hizo el cutover. Calculaba C1 y C2 sumando
las unidades de todas las unidades de medida en un solo número, que es el error
que la v3 corrige.

Quedaron objetos huérfanos en la base que dbt ya no administra y que se dan de
baja con `analyses/limpiar_objetos_mayoristas_v2.sql`. Uno merece atención:
`marts_mayoristas.mayoristas_v3_detalle_unidad`, de 774.619 filas, la escribía el
notebook por pandas antes del port a dbt. Tiene las mismas nueve columnas en el
mismo orden que `mayoristas_v3_metricas_unidad`, que es su reemplazo. Un tablero
de Power BI viejo la consulta directo, con `Item="mayoristas_v3_detalle_unidad"`
en Power Query, así que hay que repuntarlo antes de borrarla.

## El notebook

`analisis_mayorista/analisis_mayoristas_v3.ipynb` ya no escribe ninguna de estas
tablas. Queda para la parte exploratoria que motivó el rediseño, los boxplots y
las medidas de forma sobre la mezcla de unidades, y para leer estas tablas y
revisar casos puntuales. La validación de resultados vive aparte, en
`validacion_mayoristas_v3.ipynb`.
