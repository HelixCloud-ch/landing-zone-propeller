-- Stand-in for the RDS role that cdc-prepare-postgresql grants. On RDS it gives
-- the right to use logical replication; here it is an empty role, so a test
-- user cannot create a slot.
CREATE ROLE rds_replication;

CREATE TABLE public.orders (id integer PRIMARY KEY, total numeric);
CREATE TABLE public.items (id integer PRIMARY KEY, name text);
