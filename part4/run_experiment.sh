#!/bin/bash

# Set up logging
mkdir -p ../data/part4
exec > >(tee -a ../data/part4/experiment_log.txt) 2>&1

CLIENT_AGENT_NODE_NAME=$(kubectl get nodes --no-headers | grep client-agent | awk '{print $1}')
CLIENT_MEASURE_NODE_NAME=$(kubectl get nodes --no-headers | grep client-measure | awk '{print $1}')
MEMCACHE_SERVER_NODE_NAME=$(kubectl get nodes --no-headers | grep memcache-server | awk '{print $1}')

INTERNAL_AGENT_IP=$(kubectl get nodes $CLIENT_AGENT_NODE_NAME -o wide | awk 'NR==2 {print $6}')
MEMCACHED_IP=$(kubectl get nodes $MEMCACHE_SERVER_NODE_NAME -o wide | awk 'NR==2 {print $6}')

echo "Client Agent Node: $CLIENT_AGENT_NODE_NAME"
echo "Client Measure Node: $CLIENT_MEASURE_NODE_NAME"
echo "Internal Agent IP: $INTERNAL_AGENT_IP"
echo "Memcached IP: $MEMCACHED_IP"

# Create directories for each interference type
for INTERFERENCE in "${INTERFERENCES[@]}"; do
  mkdir -p "../data/part1/$INTERFERENCE"
done

# Start mcperf agent on the client-agent node
echo "Starting mcperf agent on $CLIENT_AGENT_NODE_NAME..."
gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing "ubuntu@$CLIENT_AGENT_NODE_NAME" --zone europe-west1-b \
  --command "pkill mcperf || true; cd /home/ubuntu/memcache-perf-dynamic && ./mcperf -T 8 -A" &

# Give the agent time to start
sleep 5

# First load data into memcached
echo "Loading data into memcached from $CLIENT_MEASURE_NODE_NAME..."
gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing "ubuntu@$CLIENT_MEASURE_NODE_NAME" --zone europe-west1-b \
  --command "
    cd /home/ubuntu/memcache-perf-dynamic
    
    ./mcperf -s $MEMCACHED_IP --loadonly
    ./mcperf -s $MEMCACHED_IP -a $INTERNAL_AGENT_IP --noload -T 8 -C 8 -D 4 -Q 1000 -c 8 -t 10 \
      --qps_interval 2 --qps_min 5000 --qps_max 180000 &
  "

echo "Experiment completed successfully!"