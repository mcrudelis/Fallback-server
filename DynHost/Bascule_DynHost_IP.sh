#!/bin/bash

HOST=DOMAIN
LOGIN=LOGIN
PASSWORD=PASSWORD

IP=$(curl -s http://www.monip.org/ | grep "IP : " | cut -d':' -f2 | cut -d' ' -f2| cut -d'<' -f1)
python DynHost/ipcheck.py -v -a $IP $LOGIN $PASSWORD $HOST
