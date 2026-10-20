{{ config(severity='warn') }}

-- Todo cliente clasificado por Mayoristas tiene que estar en dim_cliente. La
-- dimensión se arma desde el mapeo de clientes y le cuelga la clasificación, así
-- que un cliente que Mayoristas clasificó y la dimensión no tiene significa que
-- el mapeo y las ventas se desalinearon: por ejemplo, que dim_cliente se
-- reconstruyó con un mapeo más viejo que la clasificación.
--
-- Avisa y no falla, para que una desalineación temporal entre dos corridas no
-- frene el resto del build.

select
    r.cliente_id_limpio
from {{ ref('mayoristas_v3_resumen') }} r
left join {{ ref('dim_cliente') }} d
    on r.cliente_id_limpio = d.cliente_id_limpio
where d.cliente_id_limpio is null
