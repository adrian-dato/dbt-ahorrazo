-- Baja de los objetos de Mayoristas que ya no consume nadie.
--
-- dbt no borra nada cuando se borra un modelo: deja de administrar el
-- objeto y la tabla sigue ahi, congelada en su ultima corrida, cada dia
-- mas vieja. Esto es esa limpieza, hecha a mano una sola vez.
--
-- SE QUEDAN (las 6 que consume el tablero, mas su insumo):
--   marts_mayoristas.int_mayoristas_v3_tickets_por_unidad
--   marts_mayoristas.mayoristas_v3_tickets_unidad
--   marts_mayoristas.mayoristas_v3_metricas_unidad
--   marts_mayoristas.mayoristas_v3_umbrales
--   marts_mayoristas.mayoristas_v3_resumen
--   marts_mayoristas.mayoristas_v3_frecuencia_compra
--
-- OJO CON EL ORDEN: int_mayoristas_metricas_cliente es una vista que
-- depende de int_mayoristas_umbral_ticket_grande, asi que va primero la
-- que depende. Es la unica dependencia interna que existe entre estos
-- objetos -- verificado con sys.sql_expression_dependencies.


-- ---------------------------------------------------------------------
-- 1. Modelos de la v2, ya eliminados del repo. La v3 los reemplaza
--    entero: calculaban C1/C2 con un umbral unico que mezclaba kilos,
--    unidades y litros en un solo promedio.
-- ---------------------------------------------------------------------
drop view  if exists marts_mayoristas.int_mayoristas_metricas_cliente;
drop view  if exists marts_mayoristas.int_mayoristas_umbral_ticket_grande;
drop table if exists marts_mayoristas.dim_clientes_mayoristas;


-- ---------------------------------------------------------------------
-- 2. El mart de canasta. Lo reemplaza la linea de venta importada en el
--    tablero (int_ventas_12m_tabla): mismo dato con mas grano y, a
--    diferencia de este, filtrable por cliente. El modelo ya salio del
--    repo, asi que el proximo build no lo vuelve a crear.
-- ---------------------------------------------------------------------
drop table if exists marts_mayoristas.mayoristas_v3_canasta;


-- ---------------------------------------------------------------------
-- 3. La tabla que escribia el notebook por pandas antes del port a dbt.
--    dbt nunca la administro. Mismas 9 columnas y mismo orden que
--    mayoristas_v3_metricas_unidad, que es su reemplazo directo.
-- ---------------------------------------------------------------------
drop table if exists marts_mayoristas.mayoristas_v3_detalle_unidad;


-- ---------------------------------------------------------------------
-- 4. Anterior a dbt, en dbo. clientes_mayoristas_v2 nunca se lleno (0
--    filas desde febrero). clientes_mayoristas es la tabla que leia
--    produccion antes de todo esto: 952.012 filas de febrero, sin
--    ninguna dependencia dentro de la base.
--
--    CONFIRMAR ANTES DE CORRER ESTAS DOS. sys.sql_expression_dependencies
--    solo ve consumidores de adentro de SQL Server; un .pbix viejo, un
--    Excel con conexion o un notebook de alguien no aparecen ahi. Es la
--    tabla mas vieja de la lista y la mas probable de tener un lector
--    olvidado.
-- ---------------------------------------------------------------------
-- drop table if exists dbo.clientes_mayoristas_v2;
-- drop table if exists dbo.clientes_mayoristas;


-- ---------------------------------------------------------------------
-- 5. Lo que falta revisar, porque no entro en el listado anterior.
-- ---------------------------------------------------------------------

-- El snapshot SCD2 de la v2 vive en el esquema snapshots, no en
-- marts_mayoristas, asi que la consulta de inventario no lo mostro.
-- Puede no existir si nunca corrio. Mirarlo antes de decidir: es lo unico
-- con historia mes a mes de la clasificacion, y la v3 no guarda ninguna.
-- Es historia de una metodologia que se descarto por incorrecta, pero
-- borrada no vuelve.
select
    s.name as esquema, t.name as objeto, sum(p.rows) as filas, t.create_date
from sys.objects t
inner join sys.schemas s on s.schema_id = t.schema_id
left join sys.partitions p on p.object_id = t.object_id and p.index_id in (0, 1)
where s.name = 'snapshots'
group by s.name, t.name, t.create_date
order by t.name;

-- drop table if exists snapshots.dim_clientes_mayoristas_snapshot;

-- dbo.mayoristas_cluster (385.118) y dbo.mayoristas_cluster_variables
-- (217) son de junio de 2024 y NO son de esta metodologia: salen del
-- trabajo de RFM/clustering, otro analisis. No se tocan en esta limpieza
-- -- si se dan de baja, que sea con esa decision aparte.
