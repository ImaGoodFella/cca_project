#!/bin/bash

# Set up logging
mkdir -p ../data/part4/task4_3
exec > >(tee -a ../data/part4/task4_3/experiment_log.txt) 2>&1

CLIENT_AGENT_NODE_NAME=$(kubectl get nodes --no-headers | grep client-agent | awk '{print $1}')
CLIENT_MEASURE_NODE_NAME=$(kubectl get nodes --no-headers | grep client-measure | awk '{print $1}')
MEMCACHE_SERVER_NODE_NAME=$(kubectl get nodes --no-headers | grep memcache-server | awk '{print $1}')

# Get both the internal and external IPs for better connectivity
INTERNAL_AGENT_IP=$(kubectl get nodes $CLIENT_AGENT_NODE_NAME -o wide | awk 'NR==2 {print $6}')
MEMCACHED_IP=$(kubectl get nodes $MEMCACHE_SERVER_NODE_NAME -o wide | awk 'NR==2 {print $6}')

echo "Client Agent Node: $CLIENT_AGENT_NODE_NAME"
echo "Client Measure Node: $CLIENT_MEASURE_NODE_NAME"
echo "Internal Agent IP: $INTERNAL_AGENT_IP"
echo "Memcached IP: $MEMCACHED_IP"

CORE_LIST="0,1"
NUM_THREADS=2
NUM_RUNS=3

# Create a directory for results
RESULTS_DIR="../data/part4/task4_3"

for i in $(seq 1 $NUM_RUNS); do

  # Create a unique results file for each experiment
  RESULTS_FILE="$RESULTS_DIR/mcperf_${i}.txt"
  SCHEDULER_FILE="$RESULTS_DIR/jobs_${i}.txt"

  echo "Running experiment with core list: $CORE_LIST and threads: $NUM_THREADS"
  
  # Restart memcached on the server
  echo "Restarting memcache on $MEMCACHE_SERVER_NODE_NAME..."
  gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing "ubuntu@$MEMCACHE_SERVER_NODE_NAME" --zone europe-west1-b \
    --command "
    # Disable memcached systemd service
    sudo systemctl stop memcached
    sudo systemctl disable memcached

    # Kill any existing memcached process
    sudo pkill -9 memcached || true
    sleep 1
    
    # Verify all memcached processes are gone
    if pgrep memcached; then
      echo 'Warning: memcached still running after pkill'
      sudo pkill -9 memcached || true
    fi

    # Set internal IP
    INTERNAL_IP=\$(hostname -I | awk '{print \$1}')
    echo \"Using IP: \$INTERNAL_IP for memcached\"

    # Use the actual parameters from the loop
    THREADS=$NUM_THREADS
    CORE_LIST='$CORE_LIST'
    echo \"Starting memcached with \$THREADS threads on cores \$CORE_LIST\"

    # Start memcached manually in background with output redirected
    nohup taskset -c \$CORE_LIST memcached -m 1024 -l \$INTERNAL_IP -t \$THREADS > /tmp/memcached.log 2>&1 &
    
    # Verify memcached started
    sleep 2
    if ! pgrep memcached; then
      echo 'ERROR: memcached failed to start!'
      exit 1
    fi
    
    # Show running processes
    ps aux | grep memcached | grep -v grep
    echo 'Memcached started successfully'
    "

  # Give memcache time to start
  sleep 5

  # Kill and restart mcperf agent 
  echo "Starting mcperf agent on $CLIENT_AGENT_NODE_NAME..."
  gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing "ubuntu@$CLIENT_AGENT_NODE_NAME" --zone europe-west1-b \
    --command "
    # Kill any existing mcperf processes
    sudo pkill -9 mcperf || true
    sleep 1
    
    # Make sure all processes are gone
    if pgrep mcperf; then
      echo 'Warning: mcperf still running after pkill'
      sudo pkill -9 mcperf || true
    fi
    
    cd /home/ubuntu/memcache-perf-dynamic
    
    # Start mcperf agent with more threads and redirect output
    echo 'Starting mcperf agent...'
    nohup ./mcperf -T 8 -A > /tmp/mcperf_agent.log 2>&1 &
    
    # Verify agent started
    sleep 2
    if ! pgrep mcperf; then
      echo 'ERROR: mcperf agent failed to start!'
      exit 1
    fi
    
    # Show running processes
    ps aux | grep mcperf | grep -v grep
    echo 'mcperf agent started successfully'
    "

  # Give the agent more time to start and stabilize
  sleep 10
  
  # First load data into memcached then run benchmark
  echo "Loading data into memcached from $CLIENT_MEASURE_NODE_NAME..."

  gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing "ubuntu@$CLIENT_MEASURE_NODE_NAME" --zone europe-west1-b \
    --command "
    # Kill any existing mcperf processes
    sudo pkill -9 mcperf > /dev/null 2>&1 || true  
    sleep 1
    
    cd /home/ubuntu/memcache-perf-dynamic
    
    # Load data with higher timeout
    ./mcperf -s $MEMCACHED_IP --loadonly > /dev/null 2>&1
    
    # Wait a moment after loading
    sleep 5
    
    # Run benchmark
    ./mcperf -s $MEMCACHED_IP -a $INTERNAL_AGENT_IP --noload -T 8 -C 8 -D 4 -Q 1000 -c 8 -t 840 --qps_interval 3 --qps_min 5000 --qps_max 180000 --qps_seed 2333
    " > "$RESULTS_FILE" 2>&1 &
  
  # Wait for the benchmark to finish
  memcached_process=$!

  # Copy scheduler.py to memcache server
  echo "Copying python files to memcache server..."
  gcloud compute scp --ssh-key-file ~/.ssh/cloud-computing ./*.py ubuntu@$MEMCACHE_SERVER_NODE_NAME:~ --zone europe-west1-b

  # Run scheduler.py on memcache server
  echo "Running scheduler.py on memcache server..."
  gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing "ubuntu@$MEMCACHE_SERVER_NODE_NAME" --zone europe-west1-b \
  --command "
    # Kill any existing docker processes
    docker kill \$(docker ps -a -q) > /dev/null 2>&1 || true
    
    python3 scheduler.py $MEMCACHED_IP
  " > "$SCHEDULER_FILE" 2>&1 &

  scheduler_process=$!

  wait $scheduler_process

  echo "Scheduler process completed"

  wait $memcached_process

  echo "Benchmark process completed"

  # Clean up the results file properly
  echo "Cleaning up results file..."
  # First, check if the file exists and has content
  if [ -s "$RESULTS_FILE" ]; then
    # Remove the first 3 lines once
    sed -i '1,3d' "$RESULTS_FILE"
    
    # Remove the last 10 lines with a single command
    total_lines=$(wc -l < "$RESULTS_FILE")
    if [ "$total_lines" -gt 10 ]; then
      sed -i "$((total_lines - 9)),$total_lines d" "$RESULTS_FILE"
    fi
  else
    echo "Warning: Results file is empty or does not exist"
  fi  

  echo "Results saved to $RESULTS_FILE"
  echo "Scheduler output saved to $SCHEDULER_FILE"

done

echo "All experiments completed successfully!"