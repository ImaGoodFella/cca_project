#!/bin/bash

# Set up logging
mkdir -p ../data/part4
exec > >(tee -a ../data/part4/setup_log.txt) 2>&1


# Create the cluster
echo "Creating the cluster now"

PROJECT=`gcloud config get-value project`
kops create -f part4.yaml

# Setup ssh keys
mkdir -p ~/.ssh
chmod 700 ~/.ssh
[ -f ~/.ssh/cloud-computing ] || ssh-keygen -t rsa -b 4096 -f ~/.ssh/cloud-computing
kops create secret --name part4.k8s.local sshpublickey admin -i ~/.ssh/cloud-computing.pub

# Deploy the cluster
kops update cluster --name part4.k8s.local --yes --admin

# Validate the cluster
kops validate cluster --wait 10m

# Print the cluster information
kubectl get nodes -o wide

echo "Cluster is up and running"

PARSEC_SERVER_NAME=$(kubectl get nodes -o wide | grep parsec | awk '{print $1}')
kubectl label nodes $PARSEC_SERVER_NAME cca-project-nodetype=parsec --overwrite


# Installing memcached
echo "Installing memcached..."

MEMCACHE_SERVER_NODE_NAME=$(kubectl get nodes --no-headers | grep memcache-server | awk '{print $1}')
CLIENT_AGENT_NODE_NAME=$(kubectl get nodes --no-headers | grep client-agent | awk '{print $1}')
CLIENT_MEASURE_NODE_NAME=$(kubectl get nodes --no-headers | grep client-measure | awk '{print $1}')

# Function to install dependencies on a node

THREADS=4

install_memcache() {
  local NODE_NAME=$1
  echo "Installing dependencies on $NODE_NAME..."
  
  gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing "ubuntu@$NODE_NAME" --zone europe-west1-b \
    --command "
      # Update package repositories
      sudo apt update
      
      # Install mem-cached and libmemcached-tools
      sudo apt install -y memcached libmemcached-tools
      
      # Check if memcached is installed properly
      sudo systemctl status memcached

      # Get the internal IP of the VM
      INTERNAL_IP=\$(hostname -I | awk '{print \$1}')
      
      echo \"Configuring memcached to use 1024MB RAM and listen on \$INTERNAL_IP with $THREADS threads\"
      
      # Create a backup of the original config
      sudo cp /etc/memcached.conf /etc/memcached.conf.bak
      
      # Update memory limit, listening IP, and number of threads
      sudo sed -i 's/^-m [0-9]\+/-m 1024/' /etc/memcached.conf
      sudo sed -i \"s/^-l [0-9.]\+/-l \$INTERNAL_IP/\" /etc/memcached.conf
      
      # Check if threads parameter already exists, otherwise add it
      if grep -q '^-t' /etc/memcached.conf; then
        sudo sed -i 's/^-t [0-9]\+/-t $THREADS/' /etc/memcached.conf
      else
        echo \"-t $THREADS\" | sudo tee -a /etc/memcached.conf
      fi
      
      # Restart memcached service
      sudo systemctl restart memcached
      
      # Verify the service is running
      sudo systemctl status memcached | grep Active
      
      # Verify the configuration
      echo \"Current memcached configuration:\"
      grep '^-[lmt]' /etc/memcached.conf

    "
}

# Function to install dependencies on a node
install_mcperf() {
  local NODE_NAME=$1
  echo "Installing dependencies on $NODE_NAME..."
  
  gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing "ubuntu@$NODE_NAME" --zone europe-west1-b \
    --command "
      # Enable source repositories for build-dep
      sudo sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources
      sudo apt-get update

      # Update package repositories
      sudo apt-get update
      
      # Install required development dependencies
      sudo apt-get install libevent-dev libzmq3-dev git make g++ --yes
      sudo apt-get build-dep memcached --yes
      
      # Clone and build memcache-perf-dynamic
      git clone https://github.com/eth-easl/memcache-perf-dynamic.git
      cd memcache-perf-dynamic
      make
    "
}

install_pythonutils() {
  local NODE_NAME=$1
  echo "Installing pythonutils on $NODE_NAME..."
  
  gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing "ubuntu@$NODE_NAME" --zone europe-west1-b \
    --command "
      # Ensure psutil is installed
      sudo apt-get update && sudo apt-get install -y python3-pip 
      pip3 install psutil --break-system-packages
      pip3 install docker --break-system-packages
    "
}

install_docker() {
  local NODE_NAME=$1
  echo "Installing Docker on $NODE_NAME..."
  
  gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing "ubuntu@$NODE_NAME" --zone europe-west1-b \
    --command "
      # Install Docker
      sudo apt-get update
      sudo apt-get install -y docker.io
      sudo systemctl start docker
      sudo systemctl enable docker
      sudo usermod -aG docker \$USER

      echo 'Downloading Docker images...'
      sudo docker pull anakli/cca:parsec_blackscholes
      sudo docker pull anakli/cca:parsec_canneal
      sudo docker pull anakli/cca:parsec_dedup
      sudo docker pull anakli/cca:parsec_ferret
      sudo docker pull anakli/cca:parsec_freqmine
      sudo docker pull anakli/cca:splash2x_radix
      sudo docker pull anakli/cca:parsec_vips
    "
}

# Install on both nodes in parallel
install_mcperf "$CLIENT_AGENT_NODE_NAME" &
AGENT_PID=$!

install_mcperf "$CLIENT_MEASURE_NODE_NAME" &
MEASURE_PID=$!

# Install on both nodes in parallel
install_memcache "$MEMCACHE_SERVER_NODE_NAME" & 
MEMCACHE_ID_PID=$!

# Wait for both installations to complete
echo "Waiting for installations to complete..."
wait $MEMCACHE_ID_PID $AGENT_PID $MEASURE_PID

install_docker "$MEMCACHE_SERVER_NODE_NAME"
install_pythonutils "$MEMCACHE_SERVER_NODE_NAME"

echo "All installations finished!"