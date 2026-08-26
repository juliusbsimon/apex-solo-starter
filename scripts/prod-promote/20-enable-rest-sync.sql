-- MANUAL, PROMOTE-ONLY: re-enable REST source sync after a PRODUCTION
-- import. Never an automatic hook (see README.md).
declare
  l_app_id constant number := __APP_ID__;
  l_n      pls_integer := 0;
begin
  apex_session.create_session(
    p_app_id => l_app_id, p_page_id => 1, p_username => 'POST_IMPORT');
  for m in (select module_static_id
            from   apex_appl_web_src_modules
            where  application_id = l_app_id) loop
    begin
      apex_rest_source_sync.enable(
        p_application_id    => l_app_id,
        p_module_static_id  => m.module_static_id);
      l_n := l_n + 1;
    exception when others then null;  -- modules without sync jobs
    end;
  end loop;
  commit;
  dbms_output.put_line(l_n||' rest sync jobs re-enabled');
end;
/
