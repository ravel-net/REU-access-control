# bas, use the --script flag:
# $ sudo ./ravel.py --topo=single,2 --script=./myscript.sh

# From within the CLI:
# ravel> ./myscript.sh
# OR
# ravel> exec ./myscript.sh

# assumes acl_start topo
orch auto on
orch load acl routing

acl addtenant alice 1 2 3 11 12 13
acl addtenant bob 4 5 14 15

acl whitelist alice bob
acl whitelist alice charlie
acl whitelist bob alice
acl whitelist charlie alice

# to test dijkstra makes path only through alice
# and bob's area
# shortest path = 1-2-6-5
# shortest with restriction = 1-2-3-4-5
rt addflow h1 h5 # alice to bob

rt addflow h4 h2 # bob to alice

rt addflow h2 h7 # alice to charlie

rt addflow h1 h3 # alice to alice

rt addflow h7 h3 # charlie to alice

rt addflow h3 h4 # alice to bob

# orch run
