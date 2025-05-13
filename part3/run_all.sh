#!/bin/bash
set -euxo pipefail

NUM_REPEATS=3

for ((i=0; i<$NUM_REPEATS; i++))
do
  bash setup_cluster.sh $i
  bash run_experiment.sh $i
  kops delete cluster part3.k8s.local --yes
done