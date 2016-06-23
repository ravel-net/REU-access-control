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
This is the custom network topology for this demo (preloaded from `~/ravel/topo/sla_topo.py`).  
Now type:
`# select * from rm;`
This is the reachability matrix of the network. We will focus on three columns: the unique flow ID (fid), source (src), and destination (dst). The rm table only shows the beginning and end of each flow; the specific route is stored in the cf (configuration) table, but for now we will only focus on the tp and rm tables.

Now, suppose we allow users to "rent" portions of the network. These users are called tenants, and the nodes they "rent" are recorded in a service-level agreement, represented by the `sla` table. Type:
`# select * from sla;`
Currently, the `sla` table consists of the 10 rows:
` name  | nodeid 
-------+--------
 alice |      1
 alice |      2
 alice |      3
 alice |     11
 alice |     12
 alice |     13
 bob   |      4
 bob   |      5
 bob   |     14
 bob   |     15`

