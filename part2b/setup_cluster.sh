#!/bin/bash

# Set up logging
mkdir -p ../data/part2b
exec > >(tee -a ../data/part2b/setup_log.txt) 2>&1


# Create the cluster
echo "Creating the cluster now"

username=lbenedett

export KOPS_STATE_STORE=gs://cca-eth-2025-group-2-$username/
export PROJECT=$(gcloud config get-value project)

temp_config=$(mktemp)
envsubst < part2b.yaml > $temp_config

kops create -f $temp_config

# Setup ssh keys
mkdir -p ~/.ssh
chmod 700 ~/.ssh
[ -f ~/.ssh/cloud-computing ] || ssh-keygen -t rsa -b 4096 -f ~/.ssh/cloud-computing
kops create secret --name part2b.k8s.local sshpublickey admin -i ~/.ssh/cloud-computing.pub

# Deploy the cluster
kops update cluster --name part2b.k8s.local --yes --admin

# Validate the cluster
kops validate cluster --wait 10m

# Print the cluster information
kubectl get nodes -o wide

echo "Cluster is up and running"