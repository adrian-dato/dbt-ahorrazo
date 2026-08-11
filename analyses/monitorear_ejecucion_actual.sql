-- No hay "% completado" nativo para un SELECT/INSERT normal en SQL
-- Server (percent_complete de sys.dm_exec_requests solo se llena para
-- operaciones puntuales -- DBCC, backup/restore, rebuild de índice --,
-- no para queries comunes). Esto es lo que sí existe: contadores
-- acumulados de trabajo real. Correr esta consulta 2 veces con ~30
-- segundos de diferencia (en SSMS/Azure Data Studio, conectado al mismo
-- server):
--   - cpu_time / reads / total_elapsed_time SUBIENDO entre las 2
--     corridas -> sigue trabajando de verdad, no está colgado.
--   - blocking_session_id distinto de NULL/0 -> lo está bloqueando OTRA
--     sesión (revisar esa session_id aparte).
--   - wait_type empieza con "LCK_" -> esperando un lock, no procesando.
--
-- Mismo enfoque que ya se usó para diagnosticar el server en
-- canibalizacion_ahorrazo (fase1_diagnostico*.sql).

select
    r.session_id,
    r.status,
    r.command,
    r.wait_type,
    r.wait_time,
    r.blocking_session_id,
    r.cpu_time,
    r.total_elapsed_time,
    r.reads,
    r.writes,
    r.percent_complete,
    s.login_name,
    t.text as sql_text
from sys.dm_exec_requests r
inner join sys.dm_exec_sessions s
    on r.session_id = s.session_id
cross apply sys.dm_exec_sql_text(r.sql_handle) t
where s.login_name = 'sa'  -- o el DB_USER que uses en .env
order by r.total_elapsed_time desc
