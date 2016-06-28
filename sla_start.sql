-------------------------------------
----- SLA DEMO STARTUP APPLICATION
-------------------------------------

/*
 * nglaeser
 * 21 Jun 2016
 */

ALTER TABLE hosts DROP COLUMN IF EXISTS tenant;
ALTER TABLE switches DROP COLUMN IF EXISTS tenant;
DROP TABLE IF EXISTS sla CASCADE;
TRUNCATE TABLE rm;

ALTER TABLE hosts ADD COLUMN tenant varchar;
ALTER TABLE switches ADD COLUMN tenant varchar;

/* keep a list of tenants */
CREATE TABLE sla (name varchar, nodeid integer);
/* INSERT INTO tenants (name, nodeid) VALUES (NEW.name, NEW.nodeid); */
INSERT INTO sla (name, nodeid) VALUES ('alice', 1), ('alice', 2), ('alice', 3), ('alice', 11), ('alice', 12), ('alice', 13);
INSERT INTO sla (name, nodeid) VALUES ('bob', 4), ('bob', 5), ('bob', 14), ('bob', 15);

/* add a column to track who 'owns' each host to the hosts table */
UPDATE hosts SET tenant = sla.name FROM sla
     WHERE hosts.hid = sla.nodeid;

/* ...and to the switch table */
UPDATE switches SET tenant = sla.name FROM sla
     WHERE switches.sid = sla.nodeid;

/* each user's visible nodes */
CREATE OR REPLACE VIEW topology_acl AS ( 
    ( SELECT 'admin' AS principal, sid, nid FROM tp )
    UNION
    ( SELECT s.name AS principal, sid, nid FROM tp, sla s
        WHERE
        tp. sid IN (SELECT nodeid FROM sla WHERE name = s.name) AND
        tp. nid IN (SELECT nodeid FROM sla WHERE name = s.name) )
);

/* current user's visible nodes (topo) */
CREATE OR REPLACE VIEW topology_tenant AS (
    SELECT sid, nid FROM topology_acl
    WHERE principal = current_user);

GRANT SELECT ON topology_tenant TO PUBLIC;

DROP TABLE IF EXISTS config_sla CASCADE;

/* whitelist for who can talk to whom */
CREATE TABLE config_sla (p1 varchar, p2 varchar);
INSERT INTO config_sla (p1, p2) VALUES ('alice', 'bob'), ('alice', 'charlie'), ('bob', 'alice'), ('charlie', 'alice');

/* add some flows to the network */
INSERT INTO rm (fid, src, dst) VALUES (1, 1, 5), (2, 4, 12), (3, 2, 17), (4, 7, 3), (5, 1, 13);

/* current user's visible network traffic */
CREATE VIEW rm_tenant AS (
    SELECT fid, src, dst FROM rm
    WHERE
    rm.src IN (
        SELECT nodeid FROM sla WHERE name IN (
            SELECT p1 FROM config_sla WHERE p2=current_user )
        UNION
        SELECT nodeid FROM sla WHERE name = current_user )
    AND /* optimize? */
    rm.dst IN (
        SELECT nodeid FROM sla WHERE name IN (
            SELECT p2 FROM config_sla WHERE p1=current_user )
        UNION
        SELECT nodeid FROM sla WHERE name = current_user )
    AND (
        rm.src IN ( SELECT nodeid FROM sla WHERE name = current_user )
        OR rm.dst IN (SELECT nodeid FROM sla WHERE name = current_user)
    )
);

GRANT SELECT, INSERT, DELETE ON rm_tenant TO PUBLIC;

/* veiws created because triggers do not support subqueries */
CREATE VIEW rm_trigger_src AS (
    SELECT nodeid FROM sla WHERE name IN (
        SELECT p1 FROM config_sla WHERE p2=current_user )
    UNION
    SELECT nodeid FROM sla WHERE name = current_user );

CREATE VIEW rm_trigger_dst AS (
    SELECT nodeid FROM sla WHERE name IN (
        SELECT p2 FROM config_sla WHERE p1=current_user )
    UNION
    SELECT nodeid FROM sla WHERE name = current_user );

DROP TABLE IF EXISTS rm_exceptions;
CREATE TABLE rm_exceptions ( name varchar );
INSERT INTO rm_exceptions (name) VALUES ('ravel');

/* trigger uses AFTER INSERT because WHEN is not supported for INSTEAD OF triggers */
/* use before trigger (be more general for complicated cases/views that aren't updatabale,
performance is better to avoid unnecessary actions 
modify/override postgres modification commands */
CREATE TRIGGER rm_modifications_trigger
    INSTEAD OF INSERT ON rm_tenant
    FOR EACH ROW
    EXECUTE PROCEDURE check_rm_table( SELECT CAST ( NEW.fid AS text ), CAST(NEW.src AS text), CAST(NEW.dst AS text));

/* write in plpy */
CREATE OR REPLACE FUNCTION check_rm_table()
RETURNS TRIGGER
AS $rm_modifications_trigger$
if plpy.execute("SELECT EXISTS( SELECT 1 FROM rm_trigger_src WHERE nodeid = " + TD['args'][1] + " ) AND (SELECT EXISTS( SELECT 1 FROM rm_trigger_dst WHERE nodeid = " + TD['args'][2] + " )) AND ( SELECT EXISTS(SELECT 1 FROM sla WHERE nodeid = " + TD['args'][1] + " AND name = current_user) OR (SELECT EXISTS(SELECT 1 FROM sla WHERE nodeid = " + TD['args'][2] + " AND name = current_user) ));"):
    plpy.execute("INSERT INTO rm (fid, src, dst) VALUES (" + TD['args'][0] + ", " + TD['args'][1] + ", " + TD['args'][2] + ");")
return None;
$rm_modifications_trigger$ LANGUAGE 'plpythonu' VOLATILE SECURITY DEFINER;

/* QUESTION: how does one restrict what public can insert? */
/* TODO: restrict what current_user can insert to only flows that comply with conditions of view */
/* TODO: make fid's automatically assigned, so that user gains as little info as possible about
        what/how many other flows there are */
