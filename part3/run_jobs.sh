#!/bin/bash
set -euxo pipefail

# Set up logging
mkdir -p ../data/part3
exec > >(tee -a ../data/part3/experiment_log.txt) 2>&1

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

CLIENT_AGENT_A_NODE_NAME=$(kubectl get nodes --no-headers | grep client-agent-a | awk '{print $1}')
CLIENT_AGENT_B_NODE_NAME=$(kubectl get nodes --no-headers | grep client-agent-b | awk '{print $1}')
CLIENT_MEASURE_NODE_NAME=$(kubectl get nodes --no-headers | grep client-measure | awk '{print $1}')

INTERNAL_AGENT_A_IP=$(kubectl get nodes $CLIENT_AGENT_A_NODE_NAME -o wide | awk 'NR==2 {print $6}')
INTERNAL_AGENT_B_IP=$(kubectl get nodes $CLIENT_AGENT_B_NODE_NAME -o wide | awk 'NR==2 {print $6}')
MEMCACHED_IP=$(kubectl get pods some-memcached -o wide | awk 'NR==2 {print $6}')

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
  echo "Starting $(i)-th run ..."
  
  PIDS=()
  for JOB_NAME in "${JOB_NAMES[@]}"; do
    run_job "$JOB_NAME" &
    PIDS+=($!)
  done

  for PID in "${PIDS[@]}"; do
    wait $PID
  done

  kubectl get pods -o json > ../data/part3/results_$(i).json 2>&1

  for JOB_NAME in "${JOB_NAMES[@]}"; do
    kubectl delete jobs $JOB_NAME
  done
done