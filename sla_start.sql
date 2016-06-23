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
/* QUESTION: how does one restrict what public can insert? */
/* TODO: restrict what current_user can insert to only flows that comply with conditions of view */
/* TODO: make fid's automatically assigned, so that user gains as little info as possible about
        what/how many other flows there are */
