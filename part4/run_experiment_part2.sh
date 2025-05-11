#!/bin/bash

# Set up logging
mkdir -p ../data/part4/task2
exec > >(tee -a ../data/part4/task2/experiment_log.txt) 2>&1

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
RESULTS_DIR="../data/part4/task2"

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
    sudo pkill -9 mcperf || true 
    sleep 1
    
    cd /home/ubuntu/memcache-perf-dynamic
    
    # Load data with higher timeout
    ./mcperf -s $MEMCACHED_IP --loadonly
    
    # Wait a moment after loading
    sleep 5
    
    # Run benchmark with more moderate parameters to avoid sync issues
    echo 'Running benchmark...'
    ./mcperf -s $MEMCACHED_IP -a $INTERNAL_AGENT_IP --noload -T 8 -C 8 -D 4 -Q 1000 -c 8 -t 600 --qps_interval 10 --qps_min 5000 --qps_max 180000
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
    docker rm \$(docker ps -a -q) > /dev/null 2>&1 || true
    
    python3 scheduler.py $MEMCACHED_IP
  " > "$SCHEDULER_FILE" 2>&1 &

  scheduler_process=$!

  wait $scheduler_process

  echo "Scheduler process completed"

  # Define timeout function
  wait_with_timeout() {
    local pid=$1
    local timeout=60  # 60 seconds timeout
    
    # Start a timer in the background
    (
      sleep $timeout
      # If still running after timeout, continue script execution
      if kill -0 $pid 2>/dev/null; then
        echo "Benchmark process taking too long (over $timeout seconds), continuing..."
      fi
    ) &
    local timer_pid=$!
    
    # Wait for the process to finish
    wait $pid 2>/dev/null || true
    
    # Kill the timer process if it's still running
    kill $timer_pid 2>/dev/null || true
  }
  
  # Wait for the benchmark with timeout
  echo "Waiting for benchmark to complete (max 61 seconds)..."

  wait_with_timeout $memcached_process

  echo "Benchmark process completed"

  echo "Results saved to $RESULTS_FILE"
  echo "Scheduler output saved to $SCHEDULER_FILE"

done

echo "All experiments completed successfully!"