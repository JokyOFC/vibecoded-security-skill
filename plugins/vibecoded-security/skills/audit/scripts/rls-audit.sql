-- vibecoded-security — Postgres/Supabase authorization catalog audit.
-- Read-only: catalog queries only. Run with psql:
--   psql "<read-only connection string>" -f rls-audit.sql
-- Exposed schemas default to 'public' and 'storage'; adjust the arrays below if
-- the project exposes other schemas through the Data API.

set default_transaction_read_only = on;

\echo '== 1. Tabelas sem RLS em schema exposto (com os grants padrão do Supabase = acesso público via API)'
select n.nspname as schema, c.relname as tabela
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where c.relkind in ('r','p') and n.nspname = any (array['public'])
  and not c.relrowsecurity
order by 1, 2;

\echo '== 2. RLS ligado sem nenhuma policy (nega tudo via API: intencional ou processo quebrado?)'
select n.nspname as schema, c.relname as tabela
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where c.relkind in ('r','p') and n.nspname = any (array['public'])
  and c.relrowsecurity
  and not exists (select 1 from pg_policies p
                  where p.schemaname = n.nspname and p.tablename = c.relname)
order by 1, 2;

\echo '== 3. Todas as policies (revisar uma a uma: true, falta de auth.uid()/tenant, user_metadata, UPDATE sem with_check)'
select schemaname, tablename, policyname, permissive, cmd, roles, qual, with_check
from pg_policies
where schemaname = any (array['public','storage'])
order by schemaname, tablename, cmd;

\echo '== 4. Views sem security_invoker (ignoram RLS) e materialized views (nunca respeitam RLS)'
select n.nspname as schema, c.relname as view, c.relkind, c.reloptions
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where c.relkind in ('v','m') and n.nspname = any (array['public'])
  and coalesce(array_to_string(c.reloptions, ','), '') !~* 'security_invoker=(true|on|1)'
order by 1, 2;

\echo '== 5. Funções SECURITY DEFINER em schema exposto (devem fixar search_path e checar permissão por dentro)'
select n.nspname as schema, p.proname as funcao, p.proconfig,
       case when exists (select 1 from pg_roles where rolname = 'anon')
            then has_function_privilege('anon', p.oid, 'execute') end as anon_executa,
       case when exists (select 1 from pg_roles where rolname = 'authenticated')
            then has_function_privilege('authenticated', p.oid, 'execute') end as authenticated_executa
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where p.prosecdef and n.nspname = any (array['public'])
order by 1, 2;

\echo '== 6. Privilégios de escrita concedidos a anon em tabelas expostas'
select table_schema, table_name, string_agg(privilege_type, ', ' order by privilege_type) as privilegios
from information_schema.role_table_grants
where grantee = 'anon' and table_schema = any (array['public'])
  and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE')
group by 1, 2
order by 1, 2;
