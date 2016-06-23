# REU-access-control

A critical but less-visited aspect of SDN today is network security. Most SDN controllers still do not implement security, and as of yet, there is not even any consensus on what the ideal security requirements are. Several approaches have been suggested in the literature, including access control lists (ACLs) and restricting the direction of information flow, but none have been implemented.

Currently, the Ravel controller exposes the entire network state to all its users. This project seeks to enhance Ravel by putting in place access control support.

To learn more, follow the demo below. You can go through the steps on your own machine by installing Ravel at [http://ravel-net.org](http://ravel-net.org).

# Notes

The demo uses the following prompt syntax:  
* `$` for Linux commands in the shell prompt
* `#` for PostgreSQL commands typed into the Postgres CLI

# Demo

Log into or SSH into the Ravel VM. In the command line, run the SQL file that contains the setup for this demo:  
`$ psql --file=./ravel/REU-access-control/sla_start.sql`

Now, connect directly to the database (i.e. the Ravel controller):  
`$ psql -d ravel`

To see what user you are connected to the database as, type  
`# select current_user;`

You should be connected as ravel. Because ravel is a superuser in the database, you should have access to all of Ravel's base tables. Type:  
`# select * from tp;`  
This is the custom network topology for this demo (preloaded from `~/ravel/topo/sla_topo.py`). For now, we need only concern ourselves with the `sid` and `nid` attributes, which, respectively, represent the unique switch ID of a component of the network and the ID of the next switch it connects to.

#Now type:  
`# select * from rm;`  
This is the reachability matrix of the network. We will focus on three columns: the unique flow ID (`fid`), source (`src`), and destination (`dst`). The rm table only shows the beginning and end of each flow; the specific route is stored in the `cf` (configuration) table, but for now we will only focus on the `tp` and `rm` tables.

# Part 1: Topology Access Control

Now, suppose we allow users to "rent" portions of the network. These users are called tenants, and the nodes they "rent" are recorded in a service-level agreement, represented by the `sla` table. Type:  
`# select * from sla;`  
Currently, the `sla` table consists of the 10 rows:  
` name  | nodeid`   
-------+--------`
 alice |      1`  
 alice |      2`  
 alice |      3`   
 alice |     11`  
 alice |     12`  
 alice |     13`   
 bob   |      4`   
 bob   |      5`  
 bob   |     14`  
 bob   |     15`

Tenants should only be able to view the topology of their part of the network. This is implemented using an access control list (ACL), a view which was created for us in the SQL file we ran at the beginning of this demo. The view has three columns: one for the principal, i.e. the user from whose perspective we wish to view the topology, and the `sid` and `nid` columns from the `tp` table that are within the user's share of the network. The user `admin` can see the entire network:  
`# select * from topology_sla;`

This ACL defines what each user's visible topology should be. The `sla_start.sql` file next defines a view called `topology_public` that consists only of the entries of the `topology_acl` view where `principal = current_user`. We then granted `SELECT` privilege on the `topology_public` table to all users. Type:  
`# select * from topology_public;`  
This yields a view with no entries, because there was no entry in the `topology_acl` table where `principal = ravel`. Let's change users:  
`# \c ravel alice`  
You should now be connected to the database `ravel` as the user alice. Note that you do not have access to any of base tables anymore:  
`# select * from tp;`  
`# select * from sla;`  
`# select * from topology_acl;`  
You do, however, have access to `topology_public` because it was granted to all users. Type:  
`# select * from topology_public;`  
Note that only the `sid` and `nid` attributes are visible, and that these only include the switches that are within alice's portion of the network.

Let's check to make sure that this works for the user bob as well.  
`# \c ravel bob`  
`# select * from tp;`  
`# select * from sla;`  
`# select * from topology_acl;`  
`# select * from topology_public;` 
Once again, bob does not have access to the `tp`, `sla`, and `topology_acl` tables, but can view the connections between the switches in his own portion of the network.

The key advantage to using a database as the central controller in an SDN is that these vies are dynamic. Let's add another tenant, charlie:  
`# \c ravel ravel`  
`# insert into sla (name, nodeid) values ('charlie', 7), ('charlie', 8), ('charlie', 17), ('charlie', 18);`  
Charlie has now rented four nodes on the network. See how the `topology_acl` view updated accordingly:   
`# select * from topology_acl;`  
and that if we log in as charlie, we can see the nodes charlie owns in `topology_public`:  
`# select * from topology_public;`  
