{% macro es_categoria_sin_asignar(columna) %}
{#
    Verdadero cuando un nivel de categoría no trae valor: NULL, vacío o el
    comodín de la fuente. La fuente lo escribe 'sin asignar.' con punto
    (59.028 productos en categoria_4, y es la única escritura que aparece
    ahí); en categoria_3 aparece sin punto. Se aceptan las dos en los
    cuatro niveles, así la regla no depende de en cuál se las encuentre.
#}
    ({{ columna }} is null
     or lower(ltrim(rtrim({{ columna }}))) in (N'', N'sin asignar', N'sin asignar.'))
{% endmacro %}


{% macro normalizar_categoria(columna) %}
{#
    Texto canónico de un nivel de categoría, para armar la ruta que se
    hashea en clave_categoria(): minúsculas, sin espacios en los extremos,
    sin acentos, y el comodín unificado en 'sin asignar'.

    El COLLATE explícito del final no es decorativo. categoria_1 y
    categoria_2 salen de stg_productos con Latin1_General_CI_AI, y
    categoria_3 a categoria_5 heredan la de la base (Modern_Spanish_CI_AS).
    Una columna que sale de una vista cuenta como columna común aunque
    haya sido forzada con COLLATE adentro de ella, así que al juntar dos
    niveles en un concat SQL Server no sabe cuál usar y falla con el
    error 446. Con el mismo COLLATE explícito en todas las salidas el
    concat funciona, y el resultado no cambia con la configuración de la
    base.

    Mismo criterio de mayúsculas y acentos que ya tienen categoria_1 y
    categoria_2 (CI_AI): 'Cámara' y 'camara' son la misma categoría.
#}
    cast(
        case
            when {{ es_categoria_sin_asignar(columna) }} then N'sin asignar'
            else translate(
                lower(ltrim(rtrim(cast({{ columna }} as nvarchar(450))))),
                N'áàâäãåéèêëíìîïóòôöõúùûüñçý',
                N'aaaaaaeeeeiiiiooooouuuuncy'
            )
        end
        as nvarchar(450)
    ) collate Latin1_General_CI_AI
{% endmacro %}


{% macro nombre_categoria(columna) %}
{#
    El nombre de un nivel tal como se lee, para mostrar. No entra en
    ninguna clave. Mismo COLLATE explícito que normalizar_categoria().
#}
    cast(
        case
            when {{ es_categoria_sin_asignar(columna) }} then N'(sin asignar)'
            else ltrim(rtrim(cast({{ columna }} as nvarchar(450))))
        end
        as nvarchar(450)
    ) collate Latin1_General_CI_AI
{% endmacro %}
