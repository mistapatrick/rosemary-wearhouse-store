-- After creating the 4 users in Authentication → Users, set their roles (edit the emails):
update profiles set role='admin', name='Developer' where email='anekwepatrick@gmail.com';
update profiles set role='owner', name='Rosemary'  where email='rosemarywearhouse@gmail.com';
-- the other two stay 'staff' (default). Optionally set their names:
-- update profiles set name='Staff 1' where email='rosemarywearhouse2@gmail.com.com';
