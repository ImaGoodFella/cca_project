#!/bin/bash
set -euxo pipefail

# Set up logging
mkdir -p ../data/part3b
exec > >(tee -a ../data/part3b/experiment_log.txt) 2>&1

NUM_REPEATS=1

JOB_NAMES=(
  "parsec-blackscholes"
  "parsec-canneal"
  "parsec-dedup"
  "parsec-ferret"
  "parsec-freqmine"
  "parsec-radix"
  "parsec-vips"
)

# Create the memcached pod
echo "Setting up memcached now"

kubectl create -f memcache.yaml
kubectl expose pod some-memcached --name some-memcached-11211 \
--type LoadBalancer --port 11211 \
--protocol TCP
sleep 60
kubectl get service some-memcached-11211

CLIENT_AGENT_A_NODE_NAME=$(kubectl get nodes --no-headers | grep client-agent-a | awk '{print $1}')
CLIENT_AGENT_B_NODE_NAME=$(kubectl get nodes --no-headers | grep client-agent-b | awk '{print $1}')
CLIENT_MEASURE_NODE_NAME=$(kubectl get nodes --no-headers | grep client-measure | awk '{print $1}')

INTERNAL_AGENT_A_IP=$(kubectl get nodes $CLIENT_AGENT_A_NODE_NAME -o wide | awk 'NR==2 {print $6}')
INTERNAL_AGENT_B_IP=$(kubectl get nodes $CLIENT_AGENT_B_NODE_NAME -o wide | awk 'NR==2 {print $6}')
MEMCACHED_IP=$(kubectl get pods some-memcached -o wide | awk 'NR==2 {print $6}')

# Start mcperf agents on the client-agent nodes
echo "Starting mcperf agent on $CLIENT_AGENT_A_NODE_NAME..."
gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing "ubuntu@$CLIENT_AGENT_A_NODE_NAME" --zone europe-west1-b \
  --command "pkill mcperf || true; ./memcache-perf-dynamic/mcperf -T 2 -A" &

echo "Starting mcperf agent on $CLIENT_AGENT_B_NODE_NAME..."
gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing "ubuntu@$CLIENT_AGENT_B_NODE_NAME" --zone europe-west1-b \
  --command "pkill mcperf || true; ./memcache-perf-dynamic/mcperf -T 4 -A" &

# Give the agents time to start
sleep 10

# Load and measure constantly memcache latency
echo "Starting measures on $CLIENT_MEASURE_NODE_NAME..."
gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing "ubuntu@$CLIENT_MEASURE_NODE_NAME" --zone europe-west1-b \
  --command "pkill mcperf || true; ./memcache-perf-dynamic/mcperf -s $MEMCACHED_IP --loadonly && ./memcache-perf-dynamic/mcperf -s $MEMCACHED_IP -a $INTERNAL_AGENT_A_IP -a $INTERNAL_AGENT_B_IP --noload -T 6 -C 4 -D 4 -Q 1000 -c 4 -t 10 --scan 30000:30500:5" \
  > "../data/part3b/mcperf_measure_log.txt" 2>&1 &

#Function to run and time a job
run_job() {
  local JOB=$1

  echo "started $JOB"
  kubectl create -f "./jobs/$JOB.yaml"

  while true; do
    STATUS=$(kubectl get jobs $JOB --no-headers | awk '{print $2}')
    if [ "$STATUS" == "Complete" ]; then
      break
    fi
    echo "Waiting for $JOB job to complete..."
    sleep 5
  done
}

for i in $(seq 0 $((NUM_REPEATS - 1))); do
  echo "Starting $i-th run ..."
  
  PIDS=()
  for JOB_NAME in "${JOB_NAMES[@]}"; do
    run_job "$JOB_NAME" &
    PIDS+=($!)
  done

  for PID in "${PIDS[@]}"; do
    wait $PID
  done

  echo "Jobs are finished"

  kubectl get pods -o json > ../data/part3b/results_$i.json 2>&1

  for JOB_NAME in "${JOB_NAMES[@]}"; do
    kubectl delete jobs $JOB_NAME
  done
done

# Load and measure constantly memcache latency
echo "Killing process on $CLIENT_MEASURE_NODE_NAME..."
gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing "ubuntu@$CLIENT_MEASURE_NODE_NAME" --zone europe-west1-b \
  --command "pkill mcperf || true"

echo "Tearing down memcache ..."
kubectl delete services some-memcached-11211
kubectl delete pods some-memcached
