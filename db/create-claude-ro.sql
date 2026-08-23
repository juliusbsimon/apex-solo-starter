--------------------------------------------------------------------------------
-- create-claude-ro.sql — read-only DB account for agent introspection
--
-- Run as an admin user (on AWS RDS: the master user), e.g.:
--   sql admin@//host:1521/service @create-claude-ro.sql
--
-- Re-runnable: existing user is kept (password untouched), grants are
-- refreshed. MUST be re-run after adding tables/views — grants do not
-- apply to future objects. Put it on the migration checklist.
--------------------------------------------------------------------------------

variable app_schema varchar2(128)
variable ro_user    varchar2(128)
variable ro_pass    varchar2(128)

-- Password is PROMPTED, hidden, at run time — never stored in this file
-- (this file is committed to git; a real password here would leak into
-- history). Only used on first creation; on re-runs enter anything.
accept ro_pass_input char prompt 'Password for the new read-only user: ' hide

begin
  :app_schema := '__SCHEMA__';                  -- the app's parsing schema
  :ro_user    := 'CLAUDE_RO';
  :ro_pass    := '&ro_pass_input';
  if :ro_pass is null or lower(:ro_pass) like 'change%' then
    raise_application_error(-20001,
      'Refusing to create user with an empty or placeholder password.');
  end if;
end;
/

declare
  e_user_exists exception;
  pragma exception_init(e_user_exists, -1920);
  v_granted  pls_integer := 0;
  v_skipped  pls_integer := 0;
begin
  ------------------------------------------------------------------
  -- 1. the user: create session only, quota 0 (can own nothing)
  ------------------------------------------------------------------
  begin
    execute immediate 'create user "'||:ro_user||'" identified by "'||:ro_pass||'"'
                    ||' default tablespace users temporary tablespace temp'
                    ||' quota 0 on users';
    dbms_output.put_line('User '||:ro_user||' created.');
  exception
    when e_user_exists then
      dbms_output.put_line('User '||:ro_user||' already exists - grants refreshed only.');
  end;

  execute immediate 'grant create session to "'||:ro_user||'"';

  ------------------------------------------------------------------
  -- 2. READ (deliberately not SELECT: READ cannot SELECT...FOR UPDATE)
  --    on every table and view in the app schema
  ------------------------------------------------------------------
  for o in (select owner, object_name
            from   all_objects
            where  owner = upper(:app_schema)
            and    object_type in ('TABLE','VIEW')
            and    object_name not like 'DBTOOLS$%'
            and    object_name not like 'DATABASECHANGELOG%')
  loop
    begin
      execute immediate 'grant read on "'||o.owner||'"."'||o.object_name
                      ||'" to "'||:ro_user||'"';
      v_granted := v_granted + 1;
    exception
      when others then v_skipped := v_skipped + 1;   -- object types that refuse grants
    end;
  end loop;

  dbms_output.put_line('READ granted on '||v_granted||' objects ('
                       ||v_skipped||' skipped).');

  ------------------------------------------------------------------
  -- 3. Dictionary access for compile-error checking.
  --    USER_/ALL_ERRORS only show objects the user owns or can access;
  --    CLAUDE_RO owns nothing and has no EXECUTE on packages, so those
  --    views are silently EMPTY for exactly the objects that matter.
  --    DBA_ERRORS / DBA_OBJECTS are what it needs. Read-only either way.
  ------------------------------------------------------------------
  begin
    execute immediate 'grant select_catalog_role to "'||:ro_user||'"';
    dbms_output.put_line('SELECT_CATALOG_ROLE granted (DBA_ERRORS, DBA_OBJECTS etc. visible).');
  exception
    when others then
      -- Not grantable by this admin (common on managed platforms).
      -- On AWS RDS, use the rdsadmin procedure per view instead:
      begin
        execute immediate
          'begin rdsadmin.rdsadmin_util.grant_sys_object(''DBA_ERRORS'','''
          ||:ro_user||''',''SELECT''); end;';
        execute immediate
          'begin rdsadmin.rdsadmin_util.grant_sys_object(''DBA_OBJECTS'','''
          ||:ro_user||''',''SELECT''); end;';
        dbms_output.put_line('RDS path: DBA_ERRORS + DBA_OBJECTS granted via rdsadmin.');
      exception
        when others then
          dbms_output.put_line('WARNING: could not grant dictionary access ('
            ||substr(sqlerrm,1,200)||'). Grant DBA_ERRORS/DBA_OBJECTS to '
            ||:ro_user||' manually.');
      end;
  end;
end;
/

--------------------------------------------------------------------------------
-- 3. verify the boundary (connect as the RO user):
--      select count(*) from __WORKSPACE__.<table>;    -- works
--      create table t(x number);             -- fails: no privilege, quota 0
--      delete from __WORKSPACE__.<table>;             -- fails: READ is not DML-capable
--------------------------------------------------------------------------------
