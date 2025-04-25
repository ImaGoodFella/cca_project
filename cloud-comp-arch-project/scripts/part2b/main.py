import os, shlex, subprocess, time, sys
from utils import *
from datetime import datetime
import yaml, re


def update_file(yaml_path, new_value):
    with open(yaml_path, 'r') as file:
        data = yaml.safe_load(file)

    # Navigate to the args list
    try:
        arg = data['spec']['template']['spec']['containers'][0]['args'][1]
    except (KeyError, IndexError, TypeError):
        raise ValueError("Invalid YAML structure. Could not find 'args' path.")
    
    # Update the -n parameter using regex
    updated_arg = re.sub('-n [0-9]', f'-n {new_value}', arg)

    data['spec']['template']['spec']['containers'][0]['args'][1] = updated_arg

    # Write updated YAML back to the file
    with open(yaml_path, 'w') as file:
        yaml.dump(data, file)

    print(f"Updated -n parameter to {new_value} in {yaml_path}")

def run_experiment(parsec_job_path, thread_number, output_path):
    print(f"Running experiment for {parsec_job_path} with {thread_number} threads.")

    # STEP 4: Update the file with the number of threads
    update_file(parsec_job_path, thread_number)

    # STEP 5: Spin up PARSEC job
    run_local_command(f"kubectl create -f {parsec_job_path}")
    wait_for_pod("parsec", "Completed")
    
    # STEP 6: Collect the logs
    job_name = get_current_job_name("parsec")
    output_pod_info, _ = run_local_command(f"kubectl get pods --selector=job-name={job_name} --output=jsonpath='{{.items[*].metadata.name}}'", True) 
    output, err_output = run_local_command(f"kubectl logs {output_pod_info}", True)

    # STEP 7: Reset state
    run_local_command("kubectl delete jobs --all")
    run_local_command("kubectl delete pods --all")

    # Write the log in a file 
    with open(os.path.join(output_path, f"log_{job_name}_{thread_number}.txt"), "w") as log_file:
        log_file.write(output)


def main():
    # STEP 1: Launch cluster
    print("Launching cluster.")
    run_local_command("/bin/bash ./scripts/part2b/launch_cluster.sh")
    
    # STEP 2: Appropriate label the parsec node
    print("Labeling parsec node.")
    parsec_node_name = get_node_property_by_index("parsec", 0)
    run_local_command(f"kubectl label nodes {parsec_node_name} cca-project-nodetype=parsec")

    # STEP 3: Start all experiments
    print("Starting all experiments.")
    output_path = make_exp_dir()
    jobs_paths = [os.path.join("parsec-benchmarks/part2b/", f) for f in os.listdir("parsec-benchmarks/part2b/")]
    for thread_number in [1, 2, 4, 8]:
        for job_path in jobs_paths:
            run_experiment(job_path, thread_number, output_path)

    # STEP 8: Delete cluster
    print("Deleting cluster.")
    run_local_command("kops delete cluster part2b.k8s.local --yes")

    
if __name__ == "__main__":
    main()
