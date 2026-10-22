-- Read-only security catalog audit for the Canonical database (run as bootstrap or another superuser).
-- Prints facts only; the release security report interprets them.
\pset footer off
\pset tuples_only on
\pset format unaligned
\set ON_ERROR_STOP on
SELECT '== version: '||current_setting('server_version')||'  ledger='||(SELECT count(*) FROM canonical_migrations.applied)||'  last='||(SELECT max(migration_name) FROM canonical_migrations.applied);
SELECT '== roles (name super login bypassrls createrole createdb inherit)';
SELECT rolname||' super='||rolsuper||' login='||rolcanlogin||' bypassrls='||rolbypassrls||' createrole='||rolcreaterole||' createdb='||rolcreatedb||' inherit='||rolinherit
  FROM pg_roles WHERE rolname LIKE 'phoenix%' ORDER BY rolname;
SELECT '== memberships (member <- role : inherit set admin)';
SELECT m.rolname||' <- '||r.rolname||' : inherit='||a.inherit_option||' set='||a.set_option||' admin='||a.admin_option
  FROM pg_auth_members a JOIN pg_roles r ON r.oid=a.roleid JOIN pg_roles m ON m.oid=a.member
 WHERE m.rolname LIKE 'phoenix%' ORDER BY 1;
SELECT '== schema privileges (role schema: usage create)';
SELECT r||' '||s||': usage='||has_schema_privilege(r,s,'USAGE')||' create='||has_schema_privilege(r,s,'CREATE')
  FROM unnest(ARRAY['phoenix_canonical_app','phoenix_canonical_reader','phoenix_canonical_context_binder','public']) r,
       unnest(ARRAY['auth','core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning','canonical_migrations','public']) s
 WHERE has_schema_privilege(r,s,'USAGE') OR has_schema_privilege(r,s,'CREATE') ORDER BY 1;
SELECT '== table privileges by role (counts over business tables)';
SELECT r||' '||p||'='||count(*) FILTER (WHERE has_table_privilege(r,c.oid,p))
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace,
       unnest(ARRAY['phoenix_canonical_app','phoenix_canonical_reader','phoenix_canonical_context_binder','phoenix_canonical_migrator']) r,
       unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) p
 WHERE n.nspname IN ('auth','core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning') AND c.relkind='r'
 GROUP BY r,p ORDER BY r,p;
SELECT '== reader readable tables';
SELECT n.nspname||'.'||c.relname||' rls='||c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN ('auth','core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning','canonical_migrations') AND c.relkind='r'
   AND has_table_privilege('phoenix_canonical_reader',c.oid,'SELECT') ORDER BY 1;
SELECT '== tables without RLS and any role privilege on them';
SELECT n.nspname||'.'||c.relname||' privileged_roles='||coalesce((SELECT string_agg(r||':'||p,',') FROM unnest(ARRAY['phoenix_canonical_app','phoenix_canonical_reader','phoenix_canonical_context_binder','public']) r, unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE']) p WHERE has_table_privilege(r,c.oid,p)),'none')
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN ('auth','core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning') AND c.relkind='r' AND NOT c.relrowsecurity ORDER BY 1;
SELECT '== RLS: tables enabled='||count(*) FILTER (WHERE c.relrowsecurity)||' forced='||count(*) FILTER (WHERE c.relforcerowsecurity)||' total='||count(*)||'  policies='||(SELECT count(*) FROM pg_policies WHERE schemaname IN ('core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning','auth'))
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN ('auth','core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning') AND c.relkind='r';
SELECT '== functions: secdef='||count(*) FILTER (WHERE p.prosecdef)||' secdef_without_search_path='||count(*) FILTER (WHERE p.prosecdef AND NOT EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig,'{}')) x WHERE x LIKE 'search_path=%'))
       ||' secdef_dynamic_sql='||count(*) FILTER (WHERE p.prosecdef AND p.prosrc ~* '\mEXECUTE\M\s|format\(')
       ||' public_execute='||count(*) FILTER (WHERE has_function_privilege('public',p.oid,'EXECUTE'))
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('auth','core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning');
SELECT '== function owners: '||string_agg(o,', ') FROM (SELECT r.rolname||'(super='||r.rolsuper||') n='||count(*) o
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace JOIN pg_roles r ON r.oid=p.proowner
 WHERE n.nspname IN ('auth','core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning') GROUP BY r.rolname,r.rolsuper) x;
SELECT '== table owners: '||string_agg(DISTINCT r.rolname,', ') FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_roles r ON r.oid=c.relowner
 WHERE n.nspname IN ('auth','core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning') AND c.relkind='r';
SELECT '== executable functions per role';
SELECT r||' '||count(*) FILTER (WHERE has_function_privilege(r,p.oid,'EXECUTE')) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace,
       unnest(ARRAY['phoenix_canonical_app','phoenix_canonical_reader','phoenix_canonical_context_binder','phoenix_canonical_migrator']) r
 WHERE n.nspname IN ('auth','core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning') GROUP BY r ORDER BY r;
SELECT '== binder executable: '||string_agg(n.nspname||'.'||p.proname,', ' ORDER BY 1) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('auth','core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning') AND has_function_privilege('phoenix_canonical_context_binder',p.oid,'EXECUTE');
SELECT '== reader executable: '||coalesce(string_agg(n.nspname||'.'||p.proname,', ' ORDER BY 1),'none') FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('auth','core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning') AND has_function_privilege('phoenix_canonical_reader',p.oid,'EXECUTE');
SELECT '== pg_hba: '||string_agg(type||' '||coalesce(array_to_string(database,','),'')||' '||coalesce(array_to_string(user_name,','),'')||' '||coalesce(address,'')||' '||auth_method, ' | ' ORDER BY line_number) FROM pg_hba_file_rules;
SELECT '== default privileges entries='||count(*) FROM pg_default_acl;
