#!/bin/bash

# Set up logging
mkdir -p ../data/part4/task1
exec > >(tee -a ../data/part4/task1/experiment_log.txt) 2>&1

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

CORE_LISTS=("0" "0,1")
NUM_THREADS=(1 2)
NUM_RUNS=3

# Create a directory for results
RESULTS_DIR="../data/part4/task1"

for i in $(seq 1 $NUM_RUNS); do
  mkdir -p "$RESULTS_DIR/run_$i"
done

# Function to start CPU monitoring in the background
start_cpu_monitoring() {
  local NODE_NAME=$1
  local OUTPUT_CSV=$2
  local INTERVAL=0.1  # Monitor every 0.1 seconds
  
  echo "Starting CPU monitoring on $NODE_NAME..."
  
  # Start the monitoring script on the remote machine
  gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing "ubuntu@$NODE_NAME" --zone europe-west1-b \
    --command "
    # Create the monitoring script
    cat > /tmp/monitor_cpu.py << 'EOF'
#!/usr/bin/env python3
import psutil
import time
import sys

# Get command line arguments
interval = float(sys.argv[1])
output_file = sys.argv[2]

print(f'Starting CPU monitoring with interval={interval}s')

# Open file for writing
with open(output_file, 'w') as f:
    # Write header - only include as many cores as the system has
    cpu_count = len(psutil.cpu_percent(percpu=True))
    header = 'timestamp,' + ','.join([f'core{i}' for i in range(cpu_count)])
    f.write(header + '\n')
    f.flush()

    while True:
        # Get per-CPU utilization
        cores = psutil.cpu_percent(interval=None, percpu=True)
        t = time.time_ns()  # Use milliseconds for timestamp
        
        # Format the output line
        values = ','.join([str(core) for core in cores])
        line = f'{t},{values}'
        
        # Write to file
        f.write(line + '\n')
        f.flush()
        
        # Sleep for the specified interval
        time.sleep(interval)
EOF
    
    # Make the script executable
    chmod +x /tmp/monitor_cpu.py
    
    # Kill any existing monitoring scripts
    pkill monitor_cpu.py || true
    sleep 1

    # Start the monitoring script in the background
    nohup python3 /tmp/monitor_cpu.py $INTERVAL /tmp/cpu_stats.csv > /tmp/monitor_cpu.log 2>&1 &
    
    # Save the PID
    echo \$! > /tmp/monitor_cpu.pid
    
    # Verify it's running
    sleep 2
    if [ -f /tmp/cpu_stats.csv ] && [ \$(wc -l < /tmp/cpu_stats.csv) -gt 1 ]; then
      echo \"CPU monitoring started successfully with PID \$(cat /tmp/monitor_cpu.pid)\"
      head -n 2 /tmp/cpu_stats.csv
    else
      echo \"ERROR: CPU monitoring failed to start properly\"
      cat /tmp/monitor_cpu.log
      exit 1
    fi
  "
    
  echo "CPU monitoring started on $NODE_NAME"
}

# Function to stop CPU monitoring and download the results
stop_cpu_monitoring() {
  local NODE_NAME=$1
  local LOCAL_CSV=$2
  
  echo "Stopping CPU monitoring on $NODE_NAME..."
  
  # Stop the monitoring process
  gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing "ubuntu@$NODE_NAME" --zone europe-west1-b \
    --command "
    if [ -f /tmp/monitor_cpu.pid ]; then
      PID=\$(cat /tmp/monitor_cpu.pid)
      echo \"Stopping CPU monitoring process with PID \$PID\"
      kill \$PID || true
      sleep 2
      
      # Force kill if still running
      if ps -p \$PID > /dev/null; then
        echo \"Process still running, force killing...\"
        kill -9 \$PID || true
      fi
      
      rm /tmp/monitor_cpu.pid
      
      # Check if data was collected
      if [ -f /tmp/cpu_stats.csv ]; then
        echo \"Collected \$(wc -l < /tmp/cpu_stats.csv) CPU samples\"
      else
        echo \"WARNING: No CPU data file found\"
      fi
    else
      echo \"No monitoring PID file found\"
    fi
    "
  
  # Download the CSV file
  echo "Downloading CPU stats from $NODE_NAME..."
  gcloud compute scp --ssh-key-file ~/.ssh/cloud-computing "ubuntu@$NODE_NAME:/tmp/cpu_stats.csv" "$LOCAL_CSV" --zone europe-west1-b
  
  # Verify the file was downloaded successfully
  if [ -f "$LOCAL_CSV" ]; then
    echo "CPU monitoring data saved to $LOCAL_CSV ($(wc -l < "$LOCAL_CSV") samples)"
  else
    echo "ERROR: Failed to download CPU data"
  fi
}

for i in $(seq 1 $NUM_RUNS); do
  for core_list in "${CORE_LISTS[@]}"; do
    for threads in "${NUM_THREADS[@]}"; do

      # Create a unique results file for each experiment
      RESULTS_FILE="$RESULTS_DIR/run_${i}/${core_list}_cpu_${threads}_threads.txt"
      CPU_CSV="$RESULTS_DIR/run_${i}/${core_list}_cpu_${threads}_threads_cpu.csv"

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
      
      # Start CPU monitoring before running the benchmark
      start_cpu_monitoring "$MEMCACHE_SERVER_NODE_NAME" "$CPU_CSV"
      sleep 2

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
        " > "$RESULTS_FILE" 2>&1
      
      # Stop CPU monitoring after benchmark completes
      stop_cpu_monitoring "$MEMCACHE_SERVER_NODE_NAME" "$CPU_CSV"
      
      echo "Experiment completed for core list: $core_list and threads: $threads"
      echo "Results saved to $RESULTS_FILE"
      echo "CPU data saved to $CPU_CSV"
    done
  done
done

echo "All experiments completed successfully!"