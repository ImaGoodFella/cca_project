#!/bin/bash

# Set up logging
mkdir -p ../data/part1
exec > >(tee -a ../data/part1/setup_log.txt) 2>&1


# Create the cluster
echo "Creating the cluster now"

username=lbenedett

export KOPS_STATE_STORE=gs://cca-eth-2025-group-2-$username/
export PROJECT=$(gcloud config get-value project)

temp_config=$(mktemp)
envsubst < part1.yaml > $temp_config

kops create -f $temp_config

# Setup ssh keys
mkdir -p ~/.ssh
chmod 700 ~/.ssh
[ -f ~/.ssh/cloud-computing ] || ssh-keygen -t rsa -b 4096 -f ~/.ssh/cloud-computing
kops create secret --name part1.k8s.local sshpublickey admin -i ~/.ssh/cloud-computing.pub

# Deploy the cluster
kops update cluster --name part1.k8s.local --yes --admin

# Validate the cluster
kops validate cluster --wait 10m

# Print the cluster information
kubectl get nodes -o wide

echo "Cluster is up and running"


# Create the memcached pod
echo "Setting up memcached now"

kubectl create -f memcache-t1-cpuset.yaml
kubectl expose pod some-memcached --name some-memcached-11211 \
--type LoadBalancer --port 11211 \
--protocol TCP
sleep 60
kubectl get service some-memcached-11211


# Installing memcached
echo "Installing memcached..."

CLIENT_AGENT_NODE_NAME=$(kubectl get nodes --no-headers | grep client-agent | awk '{print $1}')
CLIENT_MEASURE_NODE_NAME=$(kubectl get nodes --no-headers | grep client-measure | awk '{print $1}')

# Function to install dependencies on a node
install_dependencies() {
  local NODE_NAME=$1
  echo "Installing dependencies on $NODE_NAME..."
  
  gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing "ubuntu@$NODE_NAME" --zone europe-west1-b \
    --command "
      # Update package repositories
      sudo apt-get update
      
      # Install required development dependencies
      sudo apt-get install -y libevent-dev libzmq3-dev git make g++ build-essential
      
      # Enable source repositories for build-dep
      sudo sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources || true
      sudo apt-get update
      
      # Clone and build memcache-perf
      cd /home/ubuntu
      if [ ! -d \"memcache-perf\" ]; then
        git clone https://github.com/shaygalon/memcache-perf.git
      fi
      cd memcache-perf && git checkout 0afbe9b && make
    "
}

# Install on both nodes in parallel
install_dependencies "$CLIENT_AGENT_NODE_NAME" &
AGENT_PID=$!

install_dependencies "$CLIENT_MEASURE_NODE_NAME" &
MEASURE_PID=$!

# Wait for both installations to complete
echo "Waiting for installations to complete..."
wait $AGENT_PID $MEASURE_PID
echo "All installations finished!"

rm part1-subst.yaml