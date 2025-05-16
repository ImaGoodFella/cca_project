#!/bin/bash
set -euxo pipefail

NUM_REPEATS=3
username=lbenedett

export KOPS_STATE_STORE=gs://cca-eth-2025-group-2-$username/
export PROJECT=$(gcloud config get-value project)

for ((i=1; i<=$NUM_REPEATS; i++))
do
  bash setup_cluster.sh $i
  bash run_experiment.sh $i
  kops delete cluster part3.k8s.local --yes
done