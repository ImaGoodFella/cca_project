#!/bin/bash
set -euxo pipefail

# Set up logging
mkdir -p ../data/part3
exec > >(tee -a ../data/part3/setup_log.txt) 2>&1


# Create the cluster
echo "Creating the cluster now"

username=lbenedett

export KOPS_STATE_STORE=gs://cca-eth-2025-group-2-$username/
export PROJECT=$(gcloud config get-value project)

temp_config=$(mktemp)
envsubst < part3.yaml > $temp_config

kops create -f $temp_config

# Setup ssh keys
mkdir -p ~/.ssh
chmod 700 ~/.ssh
[ -f ~/.ssh/cloud-computing ] || ssh-keygen -t rsa -b 4096 -f ~/.ssh/cloud-computing
kops create secret --name part3.k8s.local sshpublickey admin -i ~/.ssh/cloud-computing.pub

# Deploy the cluster
kops update cluster --name part3.k8s.local --yes --admin

# Validate the cluster
kops validate cluster --wait 10m

# Print the cluster information
kubectl get nodes -o wide

echo "Cluster is up and running"

# Installing memcached
echo "Installing memcached..."

CLIENT_AGENT_A_NODE_NAME=$(kubectl get nodes --no-headers | grep client-agent-a | awk '{print $1}')
CLIENT_AGENT_B_NODE_NAME=$(kubectl get nodes --no-headers | grep client-agent-b | awk '{print $1}')
CLIENT_MEASURE_NODE_NAME=$(kubectl get nodes --no-headers | grep client-measure | awk '{print $1}')

# Function to install dependencies on a node
install_dependencies() {
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

# Install on both nodes in parallel
install_dependencies "$CLIENT_AGENT_A_NODE_NAME" &
AGENT_A_PID=$!

install_dependencies "$CLIENT_AGENT_B_NODE_NAME" &
AGENT_B_PID=$!

install_dependencies "$CLIENT_MEASURE_NODE_NAME" &
MEASURE_PID=$!

# Wait for both installations to complete
echo "Waiting for installations to complete..."
wait $AGENT_A_PID $AGENT_B_PID $MEASURE_PID
echo "All installations finished!"