#!/bin/bash

set -e

kops create -f part1.yaml
kops create secret --name part1.k8s.local sshpublickey admin -i ~/.ssh/cloud-computing.pub
kops update cluster --name part1.k8s.local --yes --admin
kops validate cluster --wait 10m

# kubectl get nodes -o wide
# gcloud compute --ssh-file ~/.ssh/cloud-computing ubuntu@client-agent-... --zone europe-west1-b

