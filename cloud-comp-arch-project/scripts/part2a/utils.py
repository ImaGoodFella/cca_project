import os, shlex, subprocess
from datetime import datetime
from subprocess import Popen, run

MCPATH = "/home/ubuntu/memcache-perf/mcperf"


def make_exp_dir():
    output_path = f"logs/part2a/{datetime.now().strftime("%Y_%m_%d_%H_%M_%S")}/"
    os.makedirs(output_path, exist_ok=True)
    return output_path


def get_current_job_name(job_name):
    command_line = f"kubectl get jobs"
    args = shlex.split(command_line)

    kubectl_p = Popen(args, stdout=subprocess.PIPE)
    grep_p = Popen(shlex.split(f"grep {job_name}"), stdin=kubectl_p.stdout, stdout=subprocess.PIPE, universal_newlines=True)
    kubectl_p.stdout.close()
    job_properties, err_output = grep_p.communicate()
    
    return job_properties.split()[0]

def get_node_properties(node_name):
    command_line = f"kubectl get nodes -o wide"
    args = shlex.split(command_line)

    # node_properties = subprocess.check_call(args, shell=True)
    kubectl_p = Popen(args, stdout=subprocess.PIPE)
    grep_p = Popen(shlex.split(f"grep {node_name}"), stdin=kubectl_p.stdout, stdout=subprocess.PIPE, universal_newlines=True)
    kubectl_p.stdout.close()
    node_properties, err_output = grep_p.communicate()
    return node_properties

def get_node_property_by_index(node_name, index):
    node_properties = get_node_properties(node_name)
    if node_properties == "":
        print(f"No IP was found for node named: {node_name}")
        raise ValueError(f"IP not found for {node_name}")
    else:
        return node_properties.split()[index]

def get_external_ip(node_name: str) -> str:
    return get_node_property_by_index(node_name, 6) 

def get_internal_ip(node_name: str) -> str:
    return get_node_property_by_index(node_name, 5) 

def wait_for_pod(pod_name, state):
    print(f"Waiting for pod {pod_name} to start.")

    while True:
        args = shlex.split("kubectl get pods -o wide")

        kubectl_p = Popen(args, stdout=subprocess.PIPE)
        grep_p = Popen(shlex.split(f"grep {state}"), stdin=kubectl_p.stdout, stdout=subprocess.PIPE, universal_newlines=True)
        kubectl_p.stdout.close()
        pod_properties, err_output = grep_p.communicate()
        
        if pod_properties != "":
            break

    print(f"Pod {pod_name} started.")

def get_memcached_ip() -> str:
    command_line = f"kubectl get pods -o wide"
    args = shlex.split(command_line)

    kubectl_p = Popen(args, stdout=subprocess.PIPE)
    grep_p = Popen(shlex.split(f"grep some-memcached"), stdin=kubectl_p.stdout, stdout=subprocess.PIPE, universal_newlines=True)
    kubectl_p.stdout.close()
    pods_properties, err_output = grep_p.communicate()

    if pods_properties == "":
        print(f"No IP was found for memcached pod")
        raise ValueError("IP not found for memcached")
    else:
        return pods_properties.split()[5]


def run_remote_command(remote_ip, command_line, block=True):
    args = shlex.split(f"ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/cloud-computing ubuntu@{remote_ip} " + command_line) 
    if block:
        run(args, text=True)
    else:
        p = Popen(args, stdout=subprocess.PIPE, text=True)
        return p

def run_local_command(command_line, return_output=False):
    if return_output:
        p = Popen(shlex.split(command_line), stdout=subprocess.PIPE, text=True)
        return p.communicate()
    else:
        run(shlex.split(command_line), stdout=subprocess.PIPE)

def copy_on_remote(server_ip, file_path):
    copy_command = f"scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/cloud-computing {file_path} ubuntu@{server_ip}:~/"
    scp_p = run(shlex.split(copy_command))



