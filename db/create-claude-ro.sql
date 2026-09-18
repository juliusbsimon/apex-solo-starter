--------------------------------------------------------------------------------
-- create-claude-ro.sql — CREATE the read-only DB account for agent
-- introspection. This script PROMPTS for a password, so it is for humans
-- at a terminal, run once per project.
--
-- Run as an admin user (on AWS RDS: the master user), e.g.:
--   sql admin@//host:1521/service @create-claude-ro.sql
--
-- Re-runnable: an existing user is kept (password untouched, prompt input
-- ignored) and its grants are refreshed. But for grants-only refreshes —
-- after migrations, in loops — use db/refresh-claude-ro-grants.sql instead:
-- it does the same grants with NO prompt. migrate.sh/.ps1 call that one.
--------------------------------------------------------------------------------

variable app_schema varchar2(128)
variable ro_user    varchar2(128)
variable ro_pass    varchar2(128)

-- Password is PROMPTED, hidden, at run time — never stored in this file
-- (this file is committed to git; a real password here would leak into
-- history). It is only used when the user does not exist yet:
-- if the user already exists, just press Enter.
accept ro_pass_input char prompt 'Password for read-only user (Enter if user already exists): ' hide

begin
  :app_schema := '__SCHEMA__';                  -- the app's parsing schema
  -- per-SCHEMA user: the grants below cover the whole parsing schema, so
  -- every app in this schema shares this one account. A different project
  -- in a DIFFERENT schema gets its own (one password, own grants, clean
  -- audit) - never reuse one RO account across schemas.
  :ro_user    := upper('__SCHEMA___CLAUDE_RO');
  :ro_pass    := '&ro_pass_input';
end;
/

declare
  l_exists pls_integer;
begin
  ------------------------------------------------------------------
  -- the user: create session only, quota 0 (can own nothing)
  ------------------------------------------------------------------
  select count(*) into l_exists from dba_users where username = :ro_user;
  if l_exists = 0 then
    -- creation path: a real password is required HERE, and only here
    if :ro_pass is null or lower(:ro_pass) like 'change%' then
      raise_application_error(-20001,
        'User '||:ro_user||' does not exist - re-run and supply a real password to create it.');
    end if;
    execute immediate 'create user "'||:ro_user||'" identified by "'||:ro_pass||'"'
                    ||' default tablespace users temporary tablespace temp'
                    ||' quota 0 on users';
    dbms_output.put_line('User '||:ro_user||' created.');
  else
    dbms_output.put_line('User '||:ro_user||' exists - grants refreshed only (password input ignored).');
  end if;
end;
/

-- grants live in ONE place: the promptless refresh script (@@ = same dir)
@@refresh-claude-ro-grants.sql

--------------------------------------------------------------------------------
-- verify the boundary (connect as the RO user):
--      select count(*) from __WORKSPACE__.<table>;    -- works
--      create table t(x number);             -- fails: no privilege, quota 0
--      delete from __WORKSPACE__.<table>;             -- fails: READ is not DML-capable
--------------------------------------------------------------------------------
