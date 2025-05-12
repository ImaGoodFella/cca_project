import docker
from time import sleep
from typing import List, Dict, Any
import time
from os import getpid

import psutil
import sys

from datetime import datetime
from get_qps import MemcachedStats

do_not_use_core_1 = False
verbose = False
qps_cut_off = 110000

# Start scheduler on CPU 0
p = psutil.Process(getpid())
p.cpu_affinity([0])
print(f"{datetime.now().isoformat()} start scheduler", flush=True)

# Start memcached on CPU 0 and 1
try:
    memcache_cores = [0, 1]
    memcached_id = [p.pid for p in psutil.process_iter(['name']) if p.info['name'] == 'memcached'][0]
    memcached = psutil.Process(memcached_id)
    memcached.cpu_affinity([0, 1])
    print(f"{datetime.now().isoformat()} start memcached {memcache_cores} {len(memcache_cores)}", flush=True)
except:
    pass

docker_client = docker.from_env()

image_dict = {
    "blackscholes": "anakli/cca:parsec_blackscholes",
    "canneal": "anakli/cca:parsec_canneal",
    "dedup": "anakli/cca:parsec_dedup",
    "ferret": "anakli/cca:parsec_ferret",
    "freqmine": "anakli/cca:parsec_freqmine",
    "radix": "anakli/cca:splash2x_radix",
    "vips": "anakli/cca:parsec_vips",
}

scaling = [1.70, 1.70, 1.70, 1.95, 1.95, 1.95, 1.95]
duration = [100, 220, 16, 288, 394, 43, 82]
interference = [9, 9, 10, 11, 11, 8, 11]

jobs = list(zip(image_dict.keys(), scaling, duration, interference))

start_queue = sorted(jobs, key=lambda x: (x[3], -x[2], x[1]), reverse=False)

class Job:
    def __init__(self, name, scaling, duration, inteference):
        self.name = name
        self.scaling = scaling
        self.duration = duration
        self.interference = inteference
        self.image_name = image_dict[name]
        self.container = None
        self.cpuset_cpus = ""
        self.start_time = None  # Initialize start_time to None

    def __repr__(self):
        return f"Job({self.name}, {self.scaling}, {self.duration}, {self.interference})"
    
    def is_scaling_job(self):
        return self.scaling > 1.9 and self.interference > 10
    
    def set_container(self, container):
        self.container = container
        self.start_time = time.time()
    
    def update_cpusets_cpu(self, additional_cpus):

        if additional_cpus in self.cpuset_cpus:
            # CPU already in cpuset_cpus, no need to add
            return
        
        self.cpuset_cpus += f",{additional_cpus}" if self.cpuset_cpus else additional_cpus

        self.container.reload()
        if self.container.status == 'running':
            self.container.update(cpuset_cpus=self.cpuset_cpus)

    def remove_cpu(self, cpu):
        # Fix the remove_cpu method
        cpu_list = self.cpuset_cpus.split(",")
        if cpu in cpu_list:
            cpu_list.remove(cpu)
            self.cpuset_cpus = ",".join(cpu_list)
            self.container.update(cpuset_cpus=self.cpuset_cpus)

    def runtime(self):
        if self.start_time:
            return time.time() - self.start_time
        return 0
    
    def is_finished(self):
        if not self.container:
            return False        
        try:
            self.container.reload()
            return self.container.status == 'exited'
        except:
            # Container might be removed already
            return True
        


start_queue = [Job(*job) for job in start_queue]
curr_jobs: List[Job] = []

avail_cpus = ["2", "3"]

memcached_stats = MemcachedStats(sys.argv[1])

cpu_1_used = False
cpu_1_job = None

client = docker.from_env()

polling_interval = 0.1
prev_qps = 0

while len(start_queue) > 0 or len(curr_jobs) > 0:

    # Check if any job has finished
    for job in curr_jobs:
        if job.is_finished():

            # Free up the CPUs that were allocated to this job
            job_cpus = [int(a) for a in job.cpuset_cpus.split(",")]
            for cpu in job_cpus:
                if cpu and cpu not in avail_cpus:
                    avail_cpus.append(str(cpu))
            
            curr_jobs.remove(job)
            if job == cpu_1_job:
                cpu_1_job = None

            print(f"{datetime.now().isoformat()} end {job.name}", flush=True)
            print(f"{datetime.now().isoformat()} custom {job.name} released {job_cpus}", flush=True)

    # Get the current CPU and QPS
    cpu_cores_usage = psutil.cpu_percent(interval=None, percpu=True)
    
    memcached_stats.read()
    qps = memcached_stats.last_measurements()

    if abs(prev_qps - qps) > 10000:
        if verbose: print(f"{datetime.now().isoformat()} custom memcached new QPS: {qps}", flush=True)
        prev_qps = qps

    if (qps <= qps_cut_off) and not cpu_1_used and not ("1" in avail_cpus) and not do_not_use_core_1:

        cpu_1_used = True
        
        avail_cpus.insert(0, "1")
        
        try:
            memcached.cpu_affinity([0])
        except:
            pass

        print(f"{datetime.now().isoformat()} updated_cores memcached [0]", flush=True)

    elif ("1" in avail_cpus or cpu_1_used) and not (qps <= qps_cut_off) and not do_not_use_core_1:
        
        cpu_1_used = False

        if "1" in avail_cpus:
            avail_cpus.remove("1")

        if cpu_1_job is None:
            try:
                memcached.cpu_affinity([0, 1])
            except:
                pass
            print(f"{datetime.now().isoformat()} updated_cores memcached [0, 1]", flush=True)
            continue
    
        if len(cpu_1_job.cpuset_cpus.split(",")) == 1:
            cpu_1_job.container.pause()
            curr_jobs.remove(cpu_1_job)
            start_queue.insert(0, cpu_1_job)
            cpu_1_job.cpuset_cpus = ""
            print(f"{datetime.now().isoformat()} pause {cpu_1_job.name}", flush=True)
            cpu_1_job = None
        else:
            cpu_1_job.remove_cpu("1")
            print(f"{datetime.now().isoformat()} updated_cores {cpu_1_job.name} {[int(a) for a in cpu_1_job.cpuset_cpus.split(',')]}", flush=True)
            print(f"{datetime.now().isoformat()} custom {cpu_1_job.name} released CPU 1", flush=True)

        try:
            memcached.cpu_affinity([0, 1])
        except:
            pass

        print(f"{datetime.now().isoformat()} updated_cores memcached [0, 1]", flush=True)
        


    if len(avail_cpus) == 0:
        sleep(polling_interval)
        continue
            
    avail_cpu = avail_cpus.pop(0)

    if do_not_use_core_1 and avail_cpu == "1":
        # If we are not using core 1, skip it
        continue


    # If we have a scaling job, we do not need to pop
    if len(start_queue) == 0:
        scaling_jobs = [job for job in curr_jobs if job.is_scaling_job()] or curr_jobs
    else:
        scaling_jobs = [job for job in curr_jobs if job.is_scaling_job()]

    if len(scaling_jobs) > 0:
        scaling_job = scaling_jobs[0]

        scaling_job.update_cpusets_cpu(avail_cpu)

        cpuset_cpus = [int(a) for a in scaling_job.cpuset_cpus.split(",")]

        print(f"{datetime.now().isoformat()} updated_cores {scaling_job.name} {cpuset_cpus}", flush=True)

        if avail_cpu == "1":
            cpu_1_job = scaling_job
            cpu_1_used = True

        continue
    
    if len(start_queue) == 0:
        # No more jobs to start
        sleep(polling_interval)
        continue

    #
    job = start_queue.pop(0)

    # Job already started but was paused
    if job.container is not None:
        
        curr_jobs.append(job)
        job.container.update(cpuset_cpus=avail_cpu)
        job.cpuset_cpus = avail_cpu
        job.container.unpause()
        
        if avail_cpu == "1":
            cpu_1_job = job
            cpu_1_used = True
        else:
            print(f"{datetime.now().isoformat()} updated_cores {job.name} [{avail_cpu}]", flush=True)

        print(f"{datetime.now().isoformat()} unpause {job.name}", flush=True)
        continue

    run_command = (
        "./run -a run -S splash2x -p radix -i native -n 1"
        if job.name == "radix"
        else f"./run -a run -S parsec -p {job.name} -i native -n {3 if job.is_scaling_job() else 1}"
    )
    
    container = client.containers.run(
        image=job.image_name,
        command=run_command,
        detach=True,
        remove=True,
        name="parsec-" + job.name,
        cpuset_cpus=avail_cpu,
    )

    
    job.set_container(container)
    job.cpuset_cpus = avail_cpu
    curr_jobs.append(job)

    if avail_cpu == "1":
        cpu_1_job = job
        cpu_1_used = True

    print(f"{datetime.now().isoformat()} start {job.name} {[int(a) for a in avail_cpu]} {3 if job.is_scaling_job() else 1}", flush=True)


print(f"{datetime.now().isoformat()} end scheduler", flush=True)