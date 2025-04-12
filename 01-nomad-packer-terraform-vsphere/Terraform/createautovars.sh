#!/usr/bin/bash
# ./createautovars.sh "master-test-1" "worker-test-1 worker-test-2 worker-test-3" "192.168.1.93" "192.168.1.94 192.168.1.95 192.168.1.96"

arrSERVER_NAMES=($1)
arrCLIENT_NAMES=($2)
arrSERVER_IPS=($3)
arrCLIENT_IPS=($4)

echo master_nodes = { > ips.auto.tfvars
for (( i=0; i<${#arrSERVER_NAMES[@]}; i++ ))
    do  
        echo ${arrSERVER_NAMES[i]} = \"${arrSERVER_IPS[i]}\" >> ips.auto.tfvars
    done
echo } >> ips.auto.tfvars
echo worker_nodes = { >> ips.auto.tfvars
for (( i=0; i<${#arrCLIENT_NAMES[@]}; i++ ))
    do  
        echo ${arrCLIENT_NAMES[i]} = \"${arrCLIENT_IPS[i]}\" >> ips.auto.tfvars
    done
echo } >> ips.auto.tfvars

