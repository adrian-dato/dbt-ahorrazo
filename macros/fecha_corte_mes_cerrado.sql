{% macro fecha_corte_mes_cerrado() %}
{#
    Primer día del mes actual -- límite superior EXCLUSIVO para ventanas
    móviles de meses cerrados: fecha_venta < esto equivale a "hasta el
    último día del mes anterior", sin importar qué día del mes se corra
    el modelo. Mismo criterio que ya usaba view_ventas_ahorrazo_filtradas_12m
    (CTE "limites", fecha_corte) en el legacy -- portado tal cual, no
    inventado. Combinar con dateadd(month, -N, fecha_corte_mes_cerrado())
    como límite inferior.
#}
    cast(datefromparts(year(getdate()), month(getdate()), 1) as date)
{% endmacro %}
