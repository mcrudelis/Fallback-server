#!/bin/bash

script_dir="$(dirname $(realpath $0))"

source "$script_dir/cred"

IP=$(curl -s http://www.monip.org/ | grep "IP : " | cut -d':' -f2 | cut -d' ' -f2| cut -d'<' -f1)
python2.7 "$script_dir/ipcheck.py" -v -a $IP $LOGIN $PASSWORD $HOST
