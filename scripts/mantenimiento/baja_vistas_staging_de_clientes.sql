-- Baja de las vistas staging.stg_clientes_mapeo y staging.stg_clientes_limpio.
--
-- Los dos modelos se eliminaron del repo: eran vistas que solo envolvían a
-- int_clientes_mapeo_limpio y a int_clientes_limpio, y la capa de staging no
-- debe leer de intermediate. int_ventas_elegibles y fct_ventas_36m_pivotado
-- ahora leen los modelos de intermediate directo. dbt no borra nada cuando se
-- saca un modelo, así que las vistas quedaron en la base sin quien las
-- administre.
--
-- Se corre a mano en un cliente SQL, DESPUÉS de desplegar el código nuevo en
-- el servidor y de reconstruir int_ventas_elegibles: esa vista, en su versión
-- anterior, depende de stg_clientes_mapeo, y borrarla antes la deja rota hasta
-- el próximo build.
--
-- La primera consulta tiene que volver vacía: lista lo que todavía depende de
-- cada vista dentro de SQL Server. No ve un .pbix, un Excel con conexión ni un
-- notebook.

select 'stg_clientes_mapeo' as vista, referencing_schema_name as esquema, referencing_entity_name as objeto
from sys.dm_sql_referencing_entities('staging.stg_clientes_mapeo', 'OBJECT')
union all
select 'stg_clientes_limpio', referencing_schema_name, referencing_entity_name
from sys.dm_sql_referencing_entities('staging.stg_clientes_limpio', 'OBJECT');

drop view if exists staging.stg_clientes_mapeo;
drop view if exists staging.stg_clientes_limpio;
