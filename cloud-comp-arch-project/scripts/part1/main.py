import os, shlex, subprocess 
from subprocess import Popen, run
from utils import *
from datetime import datetime


def build_mcperf_on_agent():
    agent_ip = get_external_ip("agent")
    build_mcperf_on_remote(agent_ip)

def build_mcperf_on_measure():
    measure_ip = get_external_ip("measure")
    build_mcperf_on_remote(measure_ip)

def build_mcperf():
    build_mcperf_on_agent()
    build_mcperf_on_measure()

def setup_memcached():
    command_line = "/bin/bash ./scripts/part1/launch_memcached.sh"
    run(shlex.split(command_line), stdout=subprocess.PIPE)

def setup_cluster():
    command_line = "/bin/bash ./scripts/part1/launch_cluster.sh"
    run(shlex.split(command_line), stdout=subprocess.PIPE)

def delete_cluster():
    command_line = "kops delete cluster part1.k8s.local --yes"
    args = shlex.split(command_line)
    run(args)


def run_experiment(output_path, interference_fname, repetition):
    # Start agent 
    agent_ip = get_external_ip("agent")
    agent_internal_ip = get_internal_ip("agent")
    p_agent = run_remote_command(agent_ip, f"{MCPATH} -T 8 -A", False)
    
    # Start interference 
    if interference_fname is not None:
        run(shlex.split(f"kubectl create -f interference/{interference_fname}"))

    measure_ip = get_external_ip("measure")
    memcached_ip = get_memcached_ip()
    # Start measure
    p_measure = run_remote_command(measure_ip, f"{MCPATH} -s {memcached_ip} -a {agent_internal_ip} --noload -T 8 -C 8 -D 4 -Q 1000 -c 8 -t 5 -w 2 --scan 5000:80000:5000", False)

    measure_output, measure_error = p_measure.communicate()
    p_agent.kill()
    agent_output, agent_error = p_agent.communicate()
    
    interference_name = "none"
    if interference_fname is not None:
        interference_name = os.path.splitext(interference_fname)[0]
    output_path_measure = os.path.join(output_path, f"measure_{interference_name}_{repetition}.txt")
    output_path_agent = os.path.join(output_path, f"agent_{interference_name}_{repetition}.txt")

    with open(output_path_measure, "w") as f:
        f.write(measure_output)
        if measure_error is not None:
            f.write(measure_error)
    with open(output_path_agent, "w") as f:
        f.write(agent_output)
        if agent_error is not None:
            f.write(agent_error)
    
    if interference_fname is not None:
        print(f"Deleting pod: {interference_name}")
        run(shlex.split(f"kubectl delete pods {interference_name}"))
    kill_mcperf_on_remote(measure_ip)
    kill_mcperf_on_remote(agent_ip)

def make_dirs():
    output_path = f"logs/part1/{datetime.now().strftime("%Y_%m_%d_%H_%M_%S")}/"
    os.makedirs(output_path, exist_ok=True)
    return output_path

def main():

    setup_cluster()
    setup_memcached()
    build_mcperf()

    measure_ip = get_external_ip("measure")
    memcached_ip = get_memcached_ip()
    run_remote_command(measure_ip, f"{MCPATH} -s {memcached_ip} --loadonly")
    
    output_path = make_dirs()

    interferences = [None] + os.listdir("interference")
    for idx, interference_fname in enumerate(interferences):
        print(f"Running experiment {idx + 1} with interference {interference_fname}")
        for repetition in range(3):
            run_experiment(output_path, interference_fname, repetition)

    delete_cluster()

if __name__ == "__main__":
    main()
