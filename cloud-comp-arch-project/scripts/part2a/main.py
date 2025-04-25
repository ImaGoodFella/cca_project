import os, shlex, subprocess, time, sys
from utils import *
from datetime import datetime


def run_experiment(interference_path, parsec_job_path, output_path):
    print(f"Running experiment for {interference_path}, {parsec_job_path}.")


    # STEP 3: Spin up interference
    interference_name = interference_path
    if interference_path != "none":
        interference_name = os.path.splitext(os.path.basename(interference_path))[0]
        run_local_command(f"kubectl create -f {interference_path}")

        # STEP 4: Wait for the interference to start
        # Maybe check the status with get pods?
        wait_for_pod("ibench", "Running") 

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
    with open(os.path.join(output_path, f"log_{interference_name}_{job_name}.txt"), "w") as log_file:
        log_file.write(output)


def main():
    # STEP 1: Launch cluster
    print("Launching cluster.")
    run_local_command("/bin/bash ./scripts/part2a/launch_cluster.sh")
    
    # STEP 2: Appropriate label the parsec node
    print("Labeling parsec node.")
    parsec_node_name = get_node_property_by_index("parsec", 0)
    run_local_command(f"kubectl label nodes {parsec_node_name} cca-project-nodetype=parsec")
    
    print("Starting all experiments.")
    output_path = make_exp_dir()
    interference_paths = ["none"] # [os.path.join("interference", f) for f in os.listdir("interference")]
    jobs_paths = [os.path.join("parsec-benchmarks/part2a/", f) for f in os.listdir("parsec-benchmarks/part2a/")]
    for interference_path in interference_paths:
        for job_path in jobs_paths:
            run_experiment(interference_path, job_path, output_path)

    # STEP 8: Delete cluster
    print("Deleting cluster.")
    run_local_command("kops delete cluster part2a.k8s.local --yes")

    
if __name__ == "__main__":
    main()
