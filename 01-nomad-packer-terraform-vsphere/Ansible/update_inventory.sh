#!/usr/bin/bash
# ./update_inventory.sh "master-test-1" "worker-test-1 worker-test-2 worker-test-3" "192.168.1.93" "192.168.1.94 192.168.1.95 192.168.1.96"


arrSERVER_NAMES=($1)
arrCLIENT_NAMES=($2)
arrSERVER_IPS=($3)
arrCLIENT_IPS=($4)

echo -e "\n" >> inventory
echo [nomad_consul_servers] >> inventory
for (( i=0; i<${#arrSERVER_NAMES[@]}; i++ ))
    do  
        echo ${arrSERVER_NAMES[i]} ansible_host=${arrSERVER_IPS[i]} >> inventory
    done

echo -e "\n" >> inventory
echo [nomad_consul_clients] >> inventory
for (( i=0; i<${#arrCLIENT_NAMES[@]}; i++ ))
    do  
        echo ${arrCLIENT_NAMES[i]} ansible_host=${arrCLIENT_IPS[i]} >> inventory
    done

# echo -e "\n" >> inventory
# echo [consul_server_leader] >> inventory
# echo ${arrSERVER_NAMES[0]} ansible_host=${arrSERVER_IPS[0]} >> inventory

# echo -e "\n" >> inventory
# echo [consul_servers] >> inventory
# for (( i=1; i<${#arrSERVER_NAMES[@]}; i++ ))
#     do  
#         echo ${arrSERVER_NAMES[i]} ansible_host=${arrSERVER_IPS[i]} >> inventory
#     done

# echo -e "\n" >> inventory
# echo [consul_clients] >> inventory
# for (( i=0; i<${#arrCLIENT_NAMES[@]}; i++ ))
#     do  
#         echo ${arrCLIENT_NAMES[i]} ansible_host=${arrCLIENT_IPS[i]} >> inventory
#     done