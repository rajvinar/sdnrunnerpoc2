#!/bin/bash
set -x

echo "Waiting for 5 minutes before executing the node join script..."
sleep 300
echo "Executing the actual script now..."

counter=0
K8S_HOSTNAME=$1
STATIC_SA_HOSTNAME=$2
while ! nslookup ${STATIC_SA_HOSTNAME} &> /dev/null
do
    counter=$((counter+1))
    if [ $counter -ge 600 ]; then
        echo "Failed dnslookup for ${STATIC_SA_HOSTNAME} - DNS is not ready after waiting for 10 minutes."
        exit 1
    fi
    echo "Waiting for DNS..."
    sleep 1
done
echo "DNS is ready!"
