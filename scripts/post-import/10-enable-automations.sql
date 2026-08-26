-- Re-enable automations after import (imports always disable them).
-- Edit the list: only the automations that SHOULD be live in this app.
declare
  l_app_id constant number := __APP_ID__;
  l_n      pls_integer := 0;
  -- static IDs of automations to enable; keep in sync with intent
  type t_ids is table of varchar2(255);
  l_enable t_ids := t_ids(
    -- 'my-automation-static-id',
    -- 'another-automation'
  );
begin
  apex_session.create_session(
    p_app_id => l_app_id, p_page_id => 1, p_username => 'POST_IMPORT');
  if l_enable.count = 0 then
    -- default: enable ALL (remove this loop if some must stay disabled)
    for a in (select static_id from apex_appl_automations
              where  application_id = l_app_id) loop
      apex_automation.enable(p_application_id => l_app_id,
                             p_static_id      => a.static_id);
      l_n := l_n + 1;
    end loop;
  else
    for i in 1 .. l_enable.count loop
      apex_automation.enable(p_application_id => l_app_id,
                             p_static_id      => l_enable(i));
      l_n := l_n + 1;
    end loop;
    -- drift detector: if fewer enabled than listed, a listed automation no
    -- longer exists - investigate before trusting the schedule state
    if l_n < l_enable.count then
      dbms_output.put_line('WARNING: only '||l_n||' of '||l_enable.count||' listed automations found');
    end if;
  end if;
  commit;
  dbms_output.put_line(l_n||' automations re-enabled');
end;
/
