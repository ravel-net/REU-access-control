# bash, use the --script flag:
# $ sudo ./ravel.py --topo=single,2 --script=./myscript.sh

# From within the CLI:
# ravel> ./myscript.sh
# OR
# ravel> exec ./myscript.sh

# assumes dijkstra topo
orch auto on
orch load acl routing

acl addtenant alice 1 2 3 4 5 6 7 11 12 13 14 15 16 17

rt addflow h1 h2

orch run
