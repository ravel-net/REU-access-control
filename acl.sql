-------------------------------------
----- ACL APPLICATION
-------------------------------------

/*
 * nglaeser
 * 5 Jul 2016
 */

DROP TABLE IF EXISTS sla CASCADE;
TRUNCATE TABLE rm;

/* keep a list of tenants */
CREATE TABLE sla (name varchar, nodeid integer);
/* INSERT INTO tenants (name, nodeid) VALUES (NEW.name, NEW.nodeid); */

/* each user's visible nodes */
CREATE OR REPLACE VIEW topology_acl AS ( 
    ( SELECT 'admin' AS principal, sid, nid, isactive FROM tp )
    UNION
    ( SELECT s.name AS principal, sid, nid, isactive FROM tp, sla s
        WHERE
        tp. sid IN (SELECT nodeid FROM sla WHERE name = s.name) AND
        tp. nid IN (SELECT nodeid FROM sla WHERE name = s.name) )
);

/* current user's visible nodes (topo) */
CREATE OR REPLACE VIEW topology_tenant AS (
    SELECT sid, nid, isactive FROM topology_acl
    WHERE principal = current_user);

GRANT SELECT ON topology_tenant TO PUBLIC;

CREATE OR REPLACE VIEW sla_tenant AS (
    SELECT name, nodeid FROM sla
    WHERE name = current_user );
GRANT SELECT ON sla_tenant TO PUBLIC;

DROP TABLE IF EXISTS config_sla CASCADE;

/* whitelist for who can talk to whom */
CREATE TABLE config_sla (p1 varchar, p2 varchar);

/* veiws created because triggers do not support subqueries */
/* insertions into rm_tenant are restricted to flows that originate in tenant's area of network */
CREATE VIEW rm_trigger_src AS (
    SELECT nodeid FROM sla WHERE name = current_user );
/*this grant is fine because it only shows info the current user knows anyway */
GRANT SELECT ON rm_trigger_src TO PUBLIC;

CREATE VIEW rm_trigger_dst AS (
    SELECT nodeid FROM sla WHERE name IN (
        SELECT p2 FROM config_sla WHERE p1=current_user )
    UNION
    SELECT nodeid FROM sla WHERE name = current_user );
/* this grant is also fine (see rm_trigger_src grant) */
GRANT SELECT ON rm_trigger_dst TO PUBLIC;

DROP TABLE IF EXISTS rm_exceptions;
CREATE TABLE rm_exceptions ( name varchar );
INSERT INTO rm_exceptions (name) VALUES ('ravel');

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

/* returns true if the insertion is allowed */
CREATE OR REPLACE FUNCTION rm_boolean(newsrc varchar, newdst varchar)
RETURNS BOOLEAN AS $rm_boolean$
    SELECT (SELECT EXISTS( SELECT 1 FROM rm_trigger_src WHERE nodeid = CAST($1 AS integer) ) AND (SELECT EXISTS( SELECT 1 FROM rm_trigger_dst WHERE nodeid = CAST($2 AS integer) )) AND ( SELECT EXISTS(SELECT 1 FROM sla_tenant WHERE nodeid =  CAST($1 AS integer) ) OR (SELECT EXISTS(SELECT 1 FROM sla_tenant WHERE nodeid =  CAST($2 AS integer) ) )) OR (current_user = 'ravel') );
$rm_boolean$ LANGUAGE SQL;

/* trigger function */
/* returns NULL (i.e. no insertion done) if flow disallowed
   else, inserts the flow as requested */
CREATE OR REPLACE FUNCTION check_rm_table()
RETURNS TRIGGER
AS $rm_modifications_trigger$
BEGIN
IF NOT rm_boolean(CAST(NEW.src AS varchar), CAST(NEW.dst AS varchar)) THEN
    RETURN NULL;
END IF;
RETURN NEW;
END
$rm_modifications_trigger$ LANGUAGE 'plpgsql';

/* trigger for modifications on rm */
DROP TRIGGER IF EXISTS rm_modifications_trigger ON rm;
CREATE TRIGGER rm_modifications_trigger
    BEFORE INSERT ON rm
    FOR EACH ROW
    EXECUTE PROCEDURE check_rm_table();





CREATE OR REPLACE VIEW acl_violation AS (
    SELECT name FROM sla 
    WHERE name = current_user AND nodeid NOT IN (SELECT sid FROM topology_tenant)
    UNION
    SELECT name FROM sla
    WHERE name = current_user AND nodeid NOT IN (SELECT src FROM rm_tenant UNION SELECT dst FROM rm_tenant)
);

CREATE RULE acl_repair AS
    ON DELETE TO acl_violation
    DO INSTEAD
        DELETE FROM sla WHERE name=OLD.name;




CREATE OR REPLACE FUNCTION spv_constraint1_fun ()
RETURNS TRIGGER
AS $$
plpy.notice ("spv_constraint1_fun")
if TD["new"]["status"] == 'on':
    rm = plpy.execute ("SELECT * FROM rm_delta;")

    for t in rm:
        if t["isadd"] == 1:
            f = t["fid"]
            s = t["src"]
            d = t["dst"]
            
            tenantname = None
            tenantname = plpy.execute ("SELECT name FROM sla WHERE nodeid = " + str (s) + ";")
            pv = []
            if tenantname.nrows() == 0:
                pv = plpy.execute("""SELECT array(SELECT id1 FROM pgr_dijkstra('SELECT 1 as id, sid as source, nid as target, 1.0::float8 as cost FROM tp WHERE isactive = 1',""" +str (s) + "," + str (d)  + ",FALSE, FALSE))""")[0]['array']
            else:
                plpy.execute("CREATE OR REPLACE VIEW routingtp_tenant AS ( SELECT sid, nid, isactive FROM topology_acl WHERE principal = '" +  str(tenantname[0]["name"]) + "' UNION SELECT sid, nid, isactive FROM topology_acl WHERE principal IN (SELECT p2 FROM config_sla WHERE p1 = '" + str(tenantname[0]["name"]) + "') UNION SELECT sid, nid, isactive FROM tp WHERE sid IN (SELECT sid FROM topology_acl WHERE principal = '" + str(tenantname[0]["name"]) + "') AND nid IN (SELECT sid FROM topology_acl WHERE principal IN (SELECT p2 FROM config_sla WHERE p1 = '" + str(tenantname[0]["name"]) + "')) UNION SELECT sid, nid, isactive FROM tp WHERE nid IN (SELECT sid FROM topology_acl WHERE principal = '" + str(tenantname[0]["name"]) + "') AND sid IN (SELECT sid FROM topology_acl WHERE principal IN (SELECT p2 FROM config_sla WHERE p1 = '" + str(tenantname[0]["name"]) + "')));")
                plpy.execute("GRANT SELECT ON routingtp_tenant TO PUBLIC;") 
                plpy.execute("SET ROLE " + str (tenantname[0]["name"]) + ";")
                bool = plpy.execute("SELECT * FROM routingtp_tenant WHERE nid = " + str(d) + ";")
                if bool.nrows() != 0:
                    pv = plpy.execute("""SELECT array(SELECT id1 FROM pgr_dijkstra('SELECT 1 as id, sid as source, nid as target, 1.0::float8 as cost FROM routingtp_tenant WHERE isactive = 1',""" +str (s) + "," + str (d)  + ",FALSE, FALSE))""")[0]['array']
                plpy.execute("RESET ROLE;")

            l = len (pv)
            for i in range (l):
                if i + 2 < l:
                    plpy.execute ("INSERT INTO cf (fid,pid,sid,nid) VALUES (" + str (f) + "," + str (pv[i]) + "," +str (pv[i+1]) +"," + str (pv[i+2])+  ");")

        elif t["isadd"] == 0:
            f = t["fid"]
            plpy.execute ("DELETE FROM cf WHERE fid =" +str (f) +";")

    plpy.execute ("DELETE FROM rm_delta;")
return None;
$$ LANGUAGE 'plpythonu'; /* TODO: put back the "VOLATILE SECURITY DEFINER" restriction? */

DROP TRIGGER IF EXISTS spv_constraint1 ON p_spv;
CREATE TRIGGER spv_constraint1
       AFTER INSERT ON p_spv
       FOR EACH ROW
       EXECUTE PROCEDURE spv_constraint1_fun();




/* where does this view come in? */
DROP VIEW IF EXISTS spv CASCADE;
CREATE OR REPLACE VIEW spv AS (
       SELECT fid,
              src,
              dst,
              (SELECT array(SELECT id1 FROM pgr_dijkstra('SELECT 1 as id,
                                                     sid as source,
                                                     nid as target,
                                                     1.0::float8 as cost
                                                     FROM tp
                                                     WHERE isactive = 1', src, dst,FALSE, FALSE))) as pv
       FROM rm
);



CREATE OR REPLACE FUNCTION tp2spv_fun () RETURNS TRIGGER
AS $$
isactive = TD["new"]["isactive"]
sid = TD["new"]["sid"]
nid = TD["new"]["nid"]
if isactive == 0:
   fid_delta = plpy.execute ("SELECT fid FROM cf where (sid =" + str (sid) + "and nid =" + str (nid) +") or (sid = "+str (nid)+" and nid = "+str (sid)+");")
   if len (fid_delta) != 0:
      for fid in fid_delta:
          plpy.execute ("INSERT INTO spv_tb_del (SELECT * FROM cf WHERE fid = "+str (fid["fid"])+");")

          s = plpy.execute ("SELECT * FROM rm WHERE fid =" +str (fid["fid"]))[0]["src"]
          d = plpy.execute ("SELECT * FROM rm WHERE fid =" +str (fid["fid"]))[0]["dst"]

          tenantname = None
          tenantname = plpy.execute ("SELECT name FROM sla WHERE nodeid = " + str (s) + ";")[0]["name"]
          pv = []
          if tenantname.nrows() == 0:
              pv = plpy.execute("""SELECT array(SELECT id1 FROM pgr_dijkstra('SELECT 1 as id, sid as source, nid as target, 1.0::float8 as cost FROM tp WHERE isactive = 1',""" +str (s) + "," + str (d)  + ",FALSE, FALSE))""")[0]['array']

          else:
              plpy.execute("CREATE OR REPLACE VIEW routingtp_tenant AS ( SELECT sid, nid, isactive FROM topology_acl WHERE principal = '" +  str(tenantname[0]["name"]) + "' UNION SELECT sid, nid, isactive FROM topology_acl WHERE principal IN (SELECT p2 FROM config_sla WHERE p1 = '" + str(tenantname[0]["name"]) + "') UNION SELECT sid, nid, isactive FROM tp WHERE sid IN (SELECT sid FROM topology_acl WHERE principal = '" + str(tenantname[0]["name"]) + "') AND nid IN (SELECT sid FROM topology_acl WHERE principal IN (SELECT p2 FROM config_sla WHERE p1 = '" + str(tenantname[0]["name"]) + "')) UNION SELECT sid, nid, isactive FROM tp WHERE nid IN (SELECT sid FROM topology_acl WHERE principal = '" + str(tenantname[0]["name"]) + "') AND sid IN (SELECT sid FROM topology_acl WHERE principal IN (SELECT p2 FROM config_sla WHERE p1 = '" + str(tenantname[0]["name"]) + "')));")
              plpy.execute("GRANT SELECT ON routingtp_tenant TO PUBLIC;") 
              plpy.execute("SET ROLE " + str (tenantname[0]["name"]) + ";")
              bool = plpy.execute("SELECT * FROM routingtp_tenant WHERE nid = " + str(d) + ";")
              if bool.nrows() != 0:
                  pv = plpy.execute("""SELECT array(SELECT id1 FROM pgr_dijkstra('SELECT 1 as id, sid as source, nid as target, 1.0::float8 as cost FROM routingtp_tenant WHERE isactive = 1',""" +str (s) + "," + str (d)  + ",FALSE, FALSE))""")[0]['array']
              plpy.execute("RESET ROLE;")


          for i in range (len (pv)):
              if i + 2 < len (pv):
                  plpy.execute ("INSERT INTO spv_tb_ins (fid,pid,sid,nid) VALUES (" + str (fid["fid"]) + "," + str (pv[i]) + "," +str (pv[i+1]) +"," + str (pv[i+2])+  ");")

return None;
$$ LANGUAGE 'plpythonu'; /* VOLATILE SECURITY DEFINER; */

DROP TRIGGER IF EXISTS tp_up_spv_trigger ON tp;
CREATE TRIGGER tp_up_spv_trigger
       AFTER UPDATE ON tp
       FOR EACH ROW
       EXECUTE PROCEDURE tp2spv_fun();

/* add some flows to the network */
/* trigger is called on this insertion as well! */
/* TODO: should be done manually through routing app
INSERT INTO rm (fid, src, dst) VALUES (1, 1, 5), (2, 4, 12), (3, 2, 17), (4, 7, 3), (5, 1, 13); */
