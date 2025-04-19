#!/bin/bash

# Set up logging
mkdir -p ../data/part2a
exec > >(tee -a ../data/part2a/setup_log.txt) 2>&1


# Create the cluster
echo "Creating the cluster now"

PROJECT=`gcloud config get-value project`
kops create -f part2a.yaml

# Setup ssh keys
mkdir -p ~/.ssh
chmod 700 ~/.ssh
[ -f ~/.ssh/cloud-computing ] || ssh-keygen -t rsa -b 4096 -f ~/.ssh/cloud-computing
kops create secret --name part2a.k8s.local sshpublickey admin -i ~/.ssh/cloud-computing.pub

# Deploy the cluster
kops update cluster --name part2a.k8s.local --yes --admin

# Validate the cluster
kops validate cluster --wait 10m

# Print the cluster information
kubectl get nodes -o wide

echo "Cluster is up and running"

PARSEC_SERVER_NAME=$(kubectl get nodes -o wide | grep parsec | awk '{print $1}')
kubectl label nodes $PARSEC_SERVER_NAME cca-project-nodetype=parsec --overwrite