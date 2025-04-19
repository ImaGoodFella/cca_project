#!/bin/bash

# Set up logging
mkdir -p ../data/part2a
exec > >(tee -a ../data/part2a/setup_log.txt) 2>&1

NUM_REPEATS=1

JOB_NAMES=(
  "parsec-blackscholes"
  "parsec-canneal"
  "parsec-dedup"
  "parsec-ferret"
  "parsec-freqmine"
  "parsec-radix"
  "parsec-vips"
)

INTERFERENCES=(
  "no_interference"
  "ibench-cpu"
  "ibench-l1d"
  "ibench-l1i"
  "ibench-l2"
  "ibench-llc"
  "ibench-membw"
)

for INTERFERENCE in "${INTERFERENCES[@]}"; do
  if [ "$INTERFERENCE" != "no_interference" ]; then
      echo "Setting up interference: $INTERFERENCE"
      kubectl create -f "../interference_parsec/$INTERFERENCE.yaml"

      while true; do
        STATUS=$(kubectl get pod --no-headers | grep $INTERFERENCE | awk '{print $3}')
        if [ "$STATUS" == "Running" ]; then
          break
        fi
        echo "Waiting for $INTERFERENCE pod to start..."
        sleep 5
      done

      # Give the interference time to stabilize
      sleep 10
  fi

  for JOB_NAME in "${JOB_NAMES[@]}"; do
    for i in $(seq 0 $((NUM_REPEATS - 1))); do
      kubectl create -f "../parsec-benchmarks/part2a/$JOB_NAME.yaml"

      while true; do
        STATUS=$(kubectl get jobs $JOB_NAME --no-headers | awk '{print $2}')
        if [ "$STATUS" == "Complete" ]; then
          break
        fi
        echo "Waiting for $JOB_NAME job to complete..."
        sleep 5
      done

      mkdir -p "../data/part2a/$INTERFERENCE/$JOB_NAME"
      kubectl logs $(kubectl get pods --selector=job-name=$JOB_NAME --output=jsonpath='{.items[*].metadata.name}') \
        > "../data/part2a/$INTERFERENCE/$JOB_NAME/job_log$i.txt" 2>&1

      echo "Job $JOB_NAME completed successfully."

      # Clean up the job
      echo "Tearing down job: $JOB_NAME"
      kubectl delete jobs $JOB_NAME
    done
  done

  # Clean up the interference
  if [ "$INTERFERENCE" != "no_interference" ]; then
      echo "Tearing down interference: $INTERFERENCE"
      kubectl delete pod $INTERFERENCE

    # Wait for the interference to be completely removed
    while true; do
      STATUS=$(kubectl get pod --no-headers | grep $INTERFERENCE)
      if [ -z "$STATUS" ]; then
        break
      fi
      echo "Waiting for $INTERFERENCE pod to be completely removed..."
      sleep 5
    done
  fi
  
  echo "Interference $INTERFERENCE experiment done."
done

echo "All jobs completed successfully."