# REU-access-control

A critical but less-visited aspect of SDN today is network security. Most SDN controllers still do not implement security, and as of yet, there is not even any consensus on what the ideal security requirements are. Several approaches have been suggested in the literature, including access control lists (ACLs) and restricting the direction of information flow, but none have been implemented.

Currently, the Ravel controller exposes the entire network state to all its users. This project seeks to enhance Ravel by putting in place access control support.

To learn more, follow the demo below. You can go through the steps on your own machine by installing Ravel at [http://ravel-net.org](http://ravel-net.org).

# Notes

The demo uses the following prompt syntax:  
* `$` for Linux commands in the shell prompt (run from the home directory, `~`)
* `>` for Ravel commands typed into the Ravel CLI

# Demo

Log into or SSH into the Ravel VM. In the command line, run the SQL file that contains the setup for this demo:  
`$ psql --file=./ravel/REU-access-control/sla_start.sql`

Now, connect directly to the Ravel controller:  
`$ ./ravel/ravel.py --custom=./ravel/topo/sla_topo.py --topo=mytopo --onlydb --reconnect`  
The above command connects to the controller using a custom, predefined network topology (written for this demo and stored in the ~/ravel/topo folder with all the other topologies). For this demo, we use the `--onlydb` flag, which only starts the `ravel` database (i.e. the Ravel controller) without the Mininet network simulation (for more info, see [Part 1 of the Ravel Walkthrough](http://ravel-net.org/walkthrough#part-1-startup-options)). The `--reconnect` flag reconnects to the existing database, skipping reinit, which means the database will be configured with the setup the `~/ravel/REU-access-control/sla_start.sql` file created.

Now that we you connected to the controller, you can interact with the network through the Ravel CLI. The CLI has a built-in PostgreSQL interface, allowing the user to issue PostgreSQL commands with the prefix `p`.  
For instance, you can issue the SQL command to see what user we are connected to the database as:   
`> p select current_user;`

Since we didn't specify a user when connecting to the controller in the previous step, you should be connected as the user ravel per default. Because ravel is a superuser in the database, you should have access to all of Ravel's (the controller's) base tables. Type:  
`> p select * from tp;`  
As mentioned above, this is the custom network topology for this demo, preloaded from `~/ravel/topo/sla_topo.py`. For now, we need only concern ourselves with the `sid` and `nid` attributes, which, respectively, represent the unique switch ID of a component of the network and the ID of the next switch it connects to.

### Part 1: Topology Access Control

Now, suppose we allow users to "rent" portions of the network. These users are called tenants, and the nodes they "rent" are recorded in a service-level agreement, represented by the `sla` table. Type:  
`> p select * from sla;`  
Currently, the `sla` table consists of the 10 rows:  

| name  | nodeid |
| ------ | -------: | 
| alice | 1 |
| alice |      2 |
| alice |      3 |
| alice |     11 |
| alice |     12 |
| alice |     13 |
| bob   |      4 | 
| bob   |      5 |
| bob   |     14 |
| bob   |     15 |

Tenants should only be able to view the topology of their part of the network. This is implemented using an access control list (ACL), a view which was created for us in the SQL file we ran at the beginning of this demo. The view has three columns: one for the principal, i.e. the user from whose perspective we wish to view the topology, and the `sid` and `nid` columns from the `tp` table that are within the user's share of the network. The user admin is permitted to see the entire network, while alice only sees her own four links and bob his three links:  
`> p select * from topology_acl;`  
This ACL defines what each user's visible topology should be. 

The `sla_start.sql` file next defines a view called `topology_tenant` that consists only of the entries of the `topology_acl` view where `principal = current_user`. We then granted `SELECT` privilege on the `topology_tenant` view to all users. Type:  
`> p select * from topology_tenant;`  
This yields a view with no entries, because there is no entry in the `topology_acl` table where `principal = ravel`. 

Let's change users:  
```
> exit
$ ./ravel/ravel.py --custom=./ravel/topo/sla_topo.py --topo=mytopo --onlydb --reconnect --user=alice
```
You should now be connected to the database `ravel` as the user alice. Note that alice does not have access to any of base tables anymore:  
```
> p select * from tp;  
> p select * from sla; 
> p select * from topology_acl;
``` 
She does, however, have access to `topology_tenant` because it was granted to all users. Type:  
`> p select * from topology_tenant;`  
Note that only the `sid` and `nid` attributes are visible, and that these only include the switches that are within alice's portion of the network.

Let's check to make sure that this works for the user bob as well.  
```
> exit
$ ./ravel/ravel.py --custom=./ravel/topo/sla_topo.py --topo=mytopo --onlydb --reconnect --user=bob
> p select * from tp;
> p select * from sla;
> p select * from topology_acl;
> p select * from topology_tenant;
```
Once again, bob does not have access to the `tp`, `sla`, and `topology_acl` tables, but can view the connections between the switches in his own portion of the network.

The key advantage to using a database as the central controller in an SDN is that these views are dynamic. Let's add another tenant, charlie:  
```
> exit
$ ./ravel/ravel.py --custom=./ravel/topo/sla_topo.py --topo=mytopo --onlydb --reconnect
> p insert into sla (name, nodeid) values ('charlie', 7), ('charlie', 8), ('charlie', 17), ('charlie', 18);
```  
Charlie has now rented four nodes on the network. See that the `topology_acl` view has been updated accordingly:   
`> p select * from topology_acl;`  
and that if we log in as charlie, only see the nodes charlie owns are visible in `topology_tenant`:  
`> p select * from topology_tenant;`  

### Part 2: Network Traffic Access Control

#### Viewing Network Traffic

Now type:  
`> p select * from rm;`  
This is the reachability matrix of the network. We will focus on three columns: the unique flow ID (`fid`), source node (`src`), and destination node (`dst`). The rm table only shows the beginning and end of each flow; the specific route is stored in the `cf` (configuration) table, but for now we will only focus on the `tp` and `rm` tables.

Suppose alice is running a server and provides content to bob and charlie. Alice can communicate with bob and charlie, and they with her, but bob and charlie cannot talk to each other. This is reflected in the `config_sla` table:  
`> p select * from config_sla;`

   p1    |   p2    
--------- | ---------
 alice   | bob
 alice   | charlie
 bob     | alice
 charlie | alice

In the `sla_start.sql` file, we defined a view `rm_tenant` that only contains the entries from the `rm` table where `src` or `dst` are allowed for `current_user` (as specified in the `config_sla` table) and at least one of the `src` and `dst` nodes belong to `current_user`. Type:  
```
> exit
$ ./ravel/ravel.py --custom=./ravel/topo/sla_topo.py --topo=mytopo --onlydb --reconnect --user=alice
> p select * from rm_tenant;
```
Alice can see all five flows from the `rm` table, because they all have her as at least one endpoint, and the other endpoint is a user she has been whitelisted to talk to (or, in the case of flow 5, one of her own nodes). Similarly,  
```
> exit
$ ./ravel/ravel.py --custom=./ravel/topo/sla_topo.py --topo=mytopo --onlydb --reconnect --user=bob
> p select * from rm_tenant;
```  
shows the two flows that concern bob, and only those two flows. Bob cannot see any of the traffic within alice's part of the network, nor the communications between alice and charlie. The same thing holds for charlie.

#### Modifying Network Traffic

We also want to make sure users are only permitted to insert permitted flows into the network. This is achieved by creating what is called a trigger on the `rm_tenant` view. Every time an entry is inserted into the view, the trigger is fired (before the entry is inserted): if the new flow is not permitted, a function blocks the new insertion and the `rm` table and `rm_tenant` view remain unchanged (and thus, the network itself as well). If, on the other hand, the new flow is permitted, no preventative action is taken, so the `rm` table and `rm_tenant` views are updated accordingly, along with the network itself.  

This behavior is demonstrated in the following example.

Connect to the Ravel controller as the user ravel and remind yourself of the flows currently active in the network:
```
> exit
$ ./ravel/ravel.py --custom=./ravel/topo/sla_topo.py --topo=mytopo --onlydb --reconnect
> p select * from rm;
```
Now, switch to the user bob:
```
> exit
$ ./ravel/ravel.py --custom=./ravel/topo/sla_topo.py --topo=mytopo --onlydb --reconnect --user=bob
```
Recall that bob only has two visible flows in `rm_tenant`:  
`> p select * from rm_tenant;`  

Let's try inserting a disallowed flow into the `rm_tenant` view and see whether the changes are adopted:  
```
> p insert into rm_tenant (fid, src, dst) values (6, 5, 8);
> p select * from rm_tenant;
> exit
$ ./ravel/ravel.py --custom=./ravel/topo/sla_topo.py --topo=mytopo --onlydb --reconnect
> select * from rm;
```
Both the `rm_tenant` view and the `rm` table should be unchanged, only containing the same flows as before the insertion.

Now let's insert an allowed flow:  
```
> exit
$ ./ravel/ravel.py --custom=./ravel/topo/sla_topo.py --topo=mytopo --onlydb --reconnect --user=bob
> p insert into rm_tenant (fid, src, dst) values (6, 14, 12);
> select * from rm_tenant;
```
This change is also adopted in the `rm` base table:
```
> exit
$ ./ravel/ravel.py --custom=./ravel/topo/sla_topo.py --topo=mytopo --onlydb --reconnect
> p select * from rm;
```
Note that bob can only insert flows that initiate in his part of the network. For instance, even though bob is allowed to communicate with alice and see flows between his nodes and some of alice's (both in the direction bob to alice and alice to bob), he cannot insert a flow from alice to bob; if he issues the command
`> p insert into rm_tenant (fid, src, dst) values (7, 12, 14)`  
the change is not adopted by the network. (Note that to issue the above command you will need to exit the Ravel CLI and reconnect to the controller as bob.)


Bob can delete flows from his `rm_tenant` view, that is, flows in the network that are visible to him. For instance:  
```
> exit
$ ./ravel/ravel.py --custom=./ravel/topo/sla_topo.py --topo=mytopo --onlydb --reconnect --user=bob
> p delete from rm_tenant where fid=1;
```
Deleting a different flow in the network, one outside bob's vision, is impossible for bob because he does not have delete permission on the `rm` table, and these flows are not reflected in the `rm_tenant` view:
```
> p delete from rm_tenant where fid=3;
> p delete from rm where fid=3;
```
Neither of these commands has an effect on the flows in the network:  
```
> exit
$ ./ravel/ravel.py --custom=./ravel/topo/sla_topo.py --topo=mytopo --onlydb --reconnect
> p select * from rm;
```

To assure yourself of the flexibility of this access control policy, you can attempt similar deletions and insertions as any of the other users on the controller.
