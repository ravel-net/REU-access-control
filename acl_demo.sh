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
# acl whitelist alice charlie
acl whitelist bob alice
# acl whitelist charlie alice

# rt addflow h1 h5
# rt addflow h4 h2
# rt addflow h2 h7
# rt addflow h1 h3
# rt addflow h7 h3

# rt addflow h3 h4
# orch run
