#!/bin/bash

# Set up logging
mkdir -p ../data/part2b
exec > >(tee -a ../data/part2b/experiment_log.txt) 2>&1

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

NUM_THREADS_LIST=(
  "1"
  "2"
  "4"
  "8"
)

for NUM_THREADS in "${NUM_THREADS_LIST[@]}"; do

  for JOB_NAME in "${JOB_NAMES[@]}"; do
    for i in $(seq 0 $((NUM_REPEATS - 1))); do

      # Create a temporary file
      TEMP_FILE=$(mktemp)

      # Copy the original YAML to the temporary file
      cp "../parsec-benchmarks/part2b/$JOB_NAME.yaml" "$TEMP_FILE"

      # Update the -n value in the temporary file
      sed -i "s/-n [0-9]\+/-n $NUM_THREADS/" "$TEMP_FILE"

      # Create the job using the temporary file
      kubectl create -f "$TEMP_FILE"

      # Delete the temporary file
      rm -f "$TEMP_FILE"

      while true; do
        STATUS=$(kubectl get jobs $JOB_NAME --no-headers | awk '{print $2}')
        if [ "$STATUS" == "Complete" ]; then
          break
        fi
        echo "Waiting for $JOB_NAME job to complete..."
        sleep 5
      done

      mkdir -p "../data/part2b/$JOB_NAME/$NUM_THREADS/"
      kubectl logs $(kubectl get pods --selector=job-name=$JOB_NAME --output=jsonpath='{.items[*].metadata.name}') \
        > "../data/part2b/$JOB_NAME/$NUM_THREADS/job_log$i.txt" 2>&1

      echo "Job $JOB_NAME completed successfully."

      # Clean up the job
      echo "Tearing down job: $JOB_NAME"
      kubectl delete jobs $JOB_NAME
    done
  done
done  

echo "All jobs completed successfully."