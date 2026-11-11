#!/bin/bash
# Make Oracle Free look like RDS for Oracle to cdc-prepare-oracle:
# - ARCHIVELOG and supplemental logging (RDS: backup retention, alter_supplemental_logging);
# - an ADMIN user in FREEPDB1 (RDS: the master user, not SYS);
# - a stub rdsadmin.rdsadmin_util: grant_sys_object runs a plain GRANT,
#   set_configuration and alter_supplemental_logging do nothing.
# Runs once, on the first start of the container.
set -euo pipefail

sqlplus -s / as sysdba <<'SQL'
WHENEVER SQLERROR EXIT FAILURE
SHUTDOWN IMMEDIATE
STARTUP MOUNT
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
ALTER PLUGGABLE DATABASE ALL OPEN;
ALTER PLUGGABLE DATABASE ALL SAVE STATE;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (PRIMARY KEY) COLUMNS;

ALTER SESSION SET CONTAINER = FREEPDB1;

CREATE USER rdsadmin IDENTIFIED BY "Rdsadmin_1" ACCOUNT LOCK;
-- The stub grants with RDSADMIN's rights, so RDSADMIN needs each privilege
-- WITH GRANT OPTION. Same objects as CDC_SYS_OBJECT_GRANTS in prepare.py.
BEGIN
  FOR o IN (SELECT column_value AS name FROM TABLE(sys.odcivarchar2list(
      'DBMS_LOGMNR', 'DBMS_LOGMNR_D'))) LOOP
    EXECUTE IMMEDIATE 'GRANT EXECUTE ON SYS.' || o.name || ' TO rdsadmin WITH GRANT OPTION';
  END LOOP;
  FOR o IN (SELECT column_value AS name FROM TABLE(sys.odcivarchar2list(
      'V_$DATABASE', 'V_$LOG', 'V_$LOG_HISTORY', 'V_$LOGMNR_LOGS', 'V_$LOGMNR_CONTENTS',
      'V_$LOGMNR_PARAMETERS', 'V_$LOGFILE', 'V_$ARCHIVED_LOG', 'V_$ARCHIVE_DEST_STATUS',
      'V_$TRANSACTION', 'V_$MYSTAT', 'V_$STATNAME'))) LOOP
    EXECUTE IMMEDIATE 'GRANT SELECT ON SYS.' || o.name || ' TO rdsadmin WITH GRANT OPTION';
  END LOOP;
END;
/

CREATE OR REPLACE PACKAGE rdsadmin.rdsadmin_util AS
  PROCEDURE grant_sys_object(p_obj_name VARCHAR2, p_grantee VARCHAR2, p_privilege VARCHAR2);
  PROCEDURE set_configuration(name VARCHAR2, value VARCHAR2);
  PROCEDURE alter_supplemental_logging(p_action VARCHAR2, p_type VARCHAR2 DEFAULT NULL);
END;
/
CREATE OR REPLACE PACKAGE BODY rdsadmin.rdsadmin_util AS
  PROCEDURE grant_sys_object(p_obj_name VARCHAR2, p_grantee VARCHAR2, p_privilege VARCHAR2) IS
  BEGIN
    EXECUTE IMMEDIATE 'GRANT ' || p_privilege || ' ON SYS.' || p_obj_name || ' TO ' || p_grantee;
  END;
  PROCEDURE set_configuration(name VARCHAR2, value VARCHAR2) IS
  BEGIN
    NULL;
  END;
  -- Supplemental logging is turned on above, at the CDB level.
  PROCEDURE alter_supplemental_logging(p_action VARCHAR2, p_type VARCHAR2 DEFAULT NULL) IS
  BEGIN
    NULL;
  END;
END;
/

CREATE USER admin IDENTIFIED BY "adminpw";
GRANT DBA TO admin;
GRANT EXECUTE ON rdsadmin.rdsadmin_util TO admin;
EXIT
SQL

touch /tmp/cdc-ready
