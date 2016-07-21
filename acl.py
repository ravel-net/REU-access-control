"""
Access-Control application
5 Jul 2016
nglaeser
"""

from ravel.app import AppConsole

class ACLConsole(AppConsole):
    # command to add tenants to SLA table
    def do_addtenant(self, line):
        """Add a tenant to the SLA, specifying their nodes
           Usage: addtenant [name] [node] [...] [node]"""
        args = line.split()
        if len(args) < 2:
            print "Invalid syntax"
            return

        name = args[0]
        nodes = []
        
        for i in range(1, len(args)):
            try:
                nodes.append(int(args[i]))
            except Exception:
                print "Invalid node. No nodes added."
                return

            if int(args[i]) not in range(1, 21): ## TODO: hard-coded
                print "Invalid node. No nodes added."
                return

        for n in nodes:
            self.db.cursor.execute("INSERT INTO sla (name, nodeid) VALUES ('" + name + "', " + str(n) + ");")
        print "Success: added tenant " + name + " with nodes " + str(nodes)
    # TODO: make sure tenants' nodes do not overlap (i.e. both alice and bob can't rent node 6)

    def do_deltenant(self, line):
        """Delete a tenant from the SLA by name
           Usage: deltenant [name]"""
        args = line.split()
        if len(args) > 1:
            print "Invalid syntax"
            return

        name = args[0]
        self.db.cursor.execute("DELETE FROM sla WHERE name = '" + name + "';")
        print "Success: deleted tenant " + name

    # command to add communication between p1 and p2 to whitelist (i.e. config_sla)
    def do_whitelist(self, line):
        """Add a pair of tenants to the config SLA, allowing communication between A's and B's nodes (directional)
           Usage: whitelist [person1] [person2]"""
        args = line.split()
        if len(args) != 2:
            print "Invalid syntax"
            return

        p1 = args[0]
        p2 = args[1]

        # TODO: make sure both users exist
        
        self.db.cursor.execute("INSERT INTO config_sla (p1, p2) VALUES ('" + p1 + "', '" + p2 + "');")
        print "Success: added pair [" + p1 + ", " + p2 + "] to config_sla whitelist"

shortcut = "acl"
description = "an application to enforce access control"
console = ACLConsole
