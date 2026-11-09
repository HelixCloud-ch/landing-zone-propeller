-- Stand-in for the RDS procedure that cdc-prepare-mariadb calls.
CREATE PROCEDURE mysql.rds_set_configuration(IN name VARCHAR(64), IN value INT)
  SELECT name, value;
