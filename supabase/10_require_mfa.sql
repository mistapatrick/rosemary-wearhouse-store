-- Run ONLY after BOTH the owner and the admin have set up two-step sign-in (Security tab) and have signed in with a code at least once.
update settings set value='on' where key='require_mfa';
-- EMERGENCY SWITCH-OFF (lost phone): run this line in the Supabase SQL Editor instead:
-- update settings set value='off' where key='require_mfa';
