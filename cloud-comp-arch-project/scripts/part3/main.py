import os, shlex, subprocess, time, sys
from utils import *
from parse_time import *
from datetime import datetime
import yaml, re


def build_mcperf():
    for agent_name in ["agent-a", "agent-b"]:
        agent_ip = get_external_ip(agent_name)
        print(agent_ip)
        build_mcperf_on_remote(agent_ip)

    measure_ip = get_external_ip("measure")
    build_mcperf_on_remote(measure_ip)

def launch_memcached():
    command_line = "/bin/bash ./scripts/part3/launch_memcached.sh"
    run(shlex.split(command_line), stdout=subprocess.PIPE)

def launch_mcperf():
    # STEP 1: Launch the agents
    agent_a_ip = get_external_ip("agent-a")
    agent_b_ip = get_external_ip("agent-b")
    run_remote_command(agent_a_ip, f"{MCPATH} -T 2 -A", False)
    run_remote_command(agent_b_ip, f"{MCPATH} -T 4 -A", False)

    # STEP 2: Launch the measurer
    measurer_ip = get_external_ip("measure")
    agent_a_ip_internal = get_internal_ip("agent-a")
    agent_b_ip_internal = get_internal_ip("agent-b")
    memcached_ip = get_memcached_ip()
    measurer_p = run_remote_command(measurer_ip, f"{MCPATH} -s {memcached_ip} -a {agent_a_ip_internal} -a {agent_b_ip_internal} --noload -T 6 -C 4 -D 4 -Q 1000 -c 4 -t 10 --scan 30000:30500:5", False)
    return measurer_p

def launch_wait_batch_applications():
    PARSEC_DIR = "scripts/part3/parsec"

    for idx, f in enumerate(os.listdir(PARSEC_DIR)):
        # if f == "parsec-blackscholes.yaml":
        parsec_job_path = os.path.join(PARSEC_DIR, f)
        run_local_command(f"kubectl create -f {parsec_job_path}")
    
    for idx, f in enumerate(os.listdir(PARSEC_DIR)):
        # if f == "parsec-blackscholes.yaml":
        job_name = os.path.splitext(f)[0]
        wait_for_pod(job_name, "Completed")

def main():
    # run_local_command("kubectl delete jobs --all")
    # run_local_command("kubectl delete pods --all")

    # agent_a_ip = get_external_ip("agent-a")
    # agent_b_ip = get_external_ip("agent-b")
    # measurer_ip = get_external_ip("measure")

    # kill_mcperf_on_remote(measurer_ip)
    # kill_mcperf_on_remote(agent_a_ip)
    # kill_mcperf_on_remote(agent_b_ip)


    # STEP 1: Launch cluster
    print("Launching cluster.")
    run_local_command("/bin/bash ./scripts/part3/launch_cluster.sh")
    

    # STEP 2: Appropriate label the nodes
    print("Labeling parsec node.")
    for node_label in ["node-a", "node-b", "node-c", "node-d"]:
        parsec_node_name = get_node_property_by_index(node_label, 0)
        run_local_command(f"kubectl label nodes {parsec_node_name} cca-project-nodetype={node_label}")


    # STEP 3: Make mcperf on remote
    build_mcperf()


    # STEP 4: Launch memcached
    launch_memcached()


    # STEP 5: Launch mcperf
    measurer_p = launch_mcperf()


    # STEP 6: Launch and wait batch applications
    launch_wait_batch_applications()


    # STEP 7: Collect the data
    output_dir = make_exp_dir()

    with open(os.path.join(output_dir, "mcperf.txt"), "w") as f:
        measurer_p.kill()
        f.write(measurer_p.communicate()[0])

    pods_time_output, pods_time_output_err = run_local_command("kubectl get pods -o json", True)
    with open(os.path.join(output_dir, "results.json"), "w") as f:
        f.write(pods_time_output)


    # STEP 8: Delete cluster
    print("Deleting cluster.")
    # run_local_command("kops delete cluster part3.k8s.local --yes")

    
if __name__ == "__main__":
    main()
