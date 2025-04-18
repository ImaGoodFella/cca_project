#!/bin/bash

# Set up logging
mkdir -p ../data/part1
exec > >(tee -a ../data/part1/experiment_log.txt) 2>&1

NUM_REPEATS=3

INTERFERENCES=(
  "no_interference"
  "ibench-cpu"
  "ibench-l1d"
  "ibench-l1i"
  "ibench-l2"
  "ibench-llc"
  "ibench-membw"
)

CLIENT_AGENT_NODE_NAME=$(kubectl get nodes --no-headers | grep client-agent | awk '{print $1}')
CLIENT_MEASURE_NODE_NAME=$(kubectl get nodes --no-headers | grep client-measure | awk '{print $1}')

INTERNAL_AGENT_IP=$(kubectl get nodes $CLIENT_AGENT_NODE_NAME -o wide | awk 'NR==2 {print $6}')
MEMCACHED_IP=$(kubectl get pods some-memcached -o wide | awk 'NR==2 {print $6}')

# Create directories for each interference type
for INTERFERENCE in "${INTERFERENCES[@]}"; do
  mkdir -p "../data/part1/$INTERFERENCE"
done

# Start mcperf agent on the client-agent node
echo "Starting mcperf agent on $CLIENT_AGENT_NODE_NAME..."
gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing "ubuntu@$CLIENT_AGENT_NODE_NAME" --zone europe-west1-b \
  --command "pkill mcperf || true; cd /home/ubuntu/memcache-perf && ./mcperf -T 8 -A" &

# Give the agent time to start
sleep 5

# First load data into memcached
echo "Loading data into memcached from $CLIENT_MEASURE_NODE_NAME..."
gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing "ubuntu@$CLIENT_MEASURE_NODE_NAME" --zone europe-west1-b \
  --command "cd /home/ubuntu/memcache-perf && ./mcperf -s $MEMCACHED_IP --loadonly"

for INTERFERENCE in "${INTERFERENCES[@]}"; do

  echo "Running experiment with interference: $INTERFERENCE"

  if [ "$INTERFERENCE" != "no_interference" ]; then
    echo "Setting up interference: $INTERFERENCE"
    kubectl create -f "../interference/$INTERFERENCE.yaml"
    
    while true; do
      STATUS=$(kubectl get pod --no-headers | grep $INTERFERENCE | awk '{print $3}')
      if [ "$STATUS" == "Running" ]; then
        break
      fi
      echo "Waiting for $INTERFERENCE pod to start..."
      sleep 5
    done
    
    # Give the interference time to stabilize
    sleep 10
  fi

  for i in $(seq 0 $((NUM_REPEATS - 1))); do
    echo "Running test iteration $i for $INTERFERENCE..."
    # Run mcperf on the measurement node
    gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing "ubuntu@$CLIENT_MEASURE_NODE_NAME" --zone europe-west1-b \
      --command "cd /home/ubuntu/memcache-perf && ./mcperf -s $MEMCACHED_IP -a $INTERNAL_AGENT_IP \
        --noload -T 8 -C 8 -D 4 -Q 1000 -c 8 -w 2 -t 5 --scan 5000:80000:5000" > "../data/part1/$INTERFERENCE/mcperf_results$i.txt" 2>&1
  done

  if [ "$INTERFERENCE" != "no_interference" ]; then
    echo "Removing interference: $INTERFERENCE"
    kubectl delete pods $INTERFERENCE

    while kubectl get pod | grep -q "$INTERFERENCE"; do
      echo "Waiting for $INTERFERENCE pod to terminate..."
      sleep 5
    done
  fi

done

# Kill any existing mcperf processes on the client-agent node
echo "Killing any existing mcperf processes on $CLIENT_AGENT_NODE_NAME..."
gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing "ubuntu@$CLIENT_AGENT_NODE_NAME" --zone europe-west1-b \
  --command "pkill mcperf || true"

echo "Experiment completed successfully!"