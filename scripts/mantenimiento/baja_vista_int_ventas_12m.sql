-- Baja de la vista intermediate.int_ventas_12m.
--
-- El modelo se eliminó del repo: int_ventas_12m_tabla ahora lee
-- int_ventas_elegibles directo. dbt no borra nada cuando se saca un modelo,
-- así que la vista quedó en la base, sin nadie que la administre, con la
-- lista de columnas de cuando se creó.
--
-- Se corre a mano en un cliente SQL, DESPUÉS de desplegar el código nuevo en
-- el servidor. Si se corre antes, la versión vieja de int_ventas_12m_tabla,
-- que todavía hacía `select * from int_ventas_12m`, falla en la próxima
-- corrida.
--
-- Antes de borrarla, confirmar que nada la consulta. Lo que ve
-- sys.sql_expression_dependencies es solo lo de adentro de SQL Server; un
-- .pbix viejo, un Excel con conexión o un notebook no aparecen ahí.

select
    referencing_schema_name as esquema, referencing_entity_name as objeto
from sys.dm_sql_referencing_entities('intermediate.int_ventas_12m', 'OBJECT');

drop view if exists intermediate.int_ventas_12m;
