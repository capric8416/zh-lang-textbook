DROP INDEX root_super_admin_unique;
UPDATE accounts SET parent_id=NULL WHERE role='super_admin' AND parent_id='';
CREATE UNIQUE INDEX root_super_admin_unique ON accounts(role) WHERE role='super_admin' AND parent_id IS NULL;
