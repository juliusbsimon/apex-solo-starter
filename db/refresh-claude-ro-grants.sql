--------------------------------------------------------------------------------
-- refresh-claude-ro-grants.sql — re-grant READ + dictionary access to the
-- read-only agent account. NO PROMPTS: safe to run in loops and scripts
-- (migrate.sh/.ps1 run it once after migrations).
--
-- Run as an admin user (on AWS RDS: the master user), e.g.:
--   sql admin@//host:1521/service @refresh-claude-ro-grants.sql
--
-- The user must already exist — db/create-claude-ro.sql creates it (that one
-- prompts for the password; this one never asks for anything).
-- Grants do not cover future objects, so re-run this after adding tables.
--------------------------------------------------------------------------------

variable app_schema varchar2(128)
variable ro_user    varchar2(128)

begin
  :app_schema := '__SCHEMA__';                  -- the app's parsing schema
  :ro_user    := upper('__SCHEMA___CLAUDE_RO'); -- per-SCHEMA RO user (all apps in the schema share it)
end;
/

declare
  v_exists   pls_integer;
  v_granted  pls_integer := 0;
  v_skipped  pls_integer := 0;
begin
  select count(*) into v_exists from dba_users where username = :ro_user;
  if v_exists = 0 then
    raise_application_error(-20001,
      'User '||:ro_user||' does not exist - run db/create-claude-ro.sql first.');
  end if;

  execute immediate 'grant create session to "'||:ro_user||'"';

  ------------------------------------------------------------------
  -- 1. READ (deliberately not SELECT: READ cannot SELECT...FOR UPDATE)
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
  -- 2. Dictionary access for compile-error checking.
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
