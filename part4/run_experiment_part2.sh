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
RESULTS_DIR="../data/part4/task1"

for i in $(seq 1 $NUM_RUNS); do
  mkdir -p "$RESULTS_DIR/run_$i"
done


for i in $(seq 1 $NUM_RUNS); do

  # Create a unique results file for each experiment
  RESULTS_FILE="$RESULTS_DIR/run_${i}/${core_list}_cpu_${threads}_threads.txt"
  SCHEDULER_FILE="$RESULTS_DIR/run_${i}/${core_list}_scheduler_output.txt"

  echo "Running experiment with core list: $core_list and threads: $threads"
  
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
    THREADS=$threads
    CORE_LIST='$core_list'
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
    echo 'Loading data into memcached...'
    ./mcperf -s $MEMCACHED_IP --loadonly
    
    # Wait a moment after loading
    sleep 5
    
    # Run benchmark with more moderate parameters to avoid sync issues
    echo 'Running benchmark...'
    ./mcperf -s $MEMCACHED_IP -a $INTERNAL_AGENT_IP --noload -T 8 -C 8 -D 4 -Q 1000 -c 8 -t 5 --scan 5000:220000:5000
    " > "$RESULTS_FILE" 2>&1 &
  
  # Wait for the benchmark to finish
  memcached_process=$!

  # Copy scheduler.py to memcache server
  echo "Copying scheduler.py to memcache server..."
  gcloud compute scp --ssh-key-file ~/.ssh/cloud-computing ./scheduler.py ubuntu@$MEMCACHE_SERVER_NODE_NAME:~ --zone europe-west1-b

  # Run scheduler.py on memcache server
  echo "Running scheduler.py on memcache server..."
  gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing "ubuntu@$MEMCACHE_SERVER_NODE_NAME" --zone europe-west1-b \
  --command "
    python3 scheduler.py
  " > "$SCHEDULER_FILE" 2>&1 &
  scheduler_process=$!


  wait $memcached_process $scheduler_process
  
  echo "Experiment completed for core list: $core_list and threads: $threads"

  echo "Results saved to $RESULTS_FILE"
  echo "Scheduler output saved to $SCHEDULER_FILE"

done

echo "All experiments completed successfully!"