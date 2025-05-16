import matplotlib.pyplot as plt
from datetime import datetime
from collections import defaultdict
import matplotlib.cm as cm
import pandas as pd
import re
import os

def plot_job_log_file(ax, log_file):
    with open(log_file, "r") as f:
        lines = f.readlines()

    job_states = defaultdict(list)   # job -> list of (start_time, end_time)
    job_status = {}                  # job -> (status, start_time)
    job_first_start_time = {}        # job -> first start time

    time_format = "%Y-%m-%dT%H:%M:%S.%f"

    # Parse timestamps to find T0
    timestamps = []
    for line in lines:
        if line.strip():
            ts_str = line.split(" ", 1)[0]
            timestamps.append(datetime.strptime(ts_str, time_format))
    T0 = min(timestamps)

    # Process log entries
    for line in lines:
        line = line.strip()
        if not line:
            continue

        timestamp_str, rest = line.split(" ", 1)
        timestamp = datetime.strptime(timestamp_str, time_format)
        t_sec = (timestamp - T0).total_seconds()

        if rest.startswith("start"):
            job = rest.split()[1]
            if job == "scheduler":
                continue
            job_status[job] = ("running", t_sec)
            if job not in job_first_start_time:
                job_first_start_time[job] = t_sec

        elif rest.startswith("pause"):
            job = rest.split()[1]
            if job in job_status and job_status[job][0] == "running":
                start_sec = job_status[job][1]
                job_states[job].append((start_sec, t_sec))
                job_status[job] = ("paused", None)

        elif rest.startswith("unpause"):
            job = rest.split()[1]
            job_status[job] = ("running", t_sec)

        elif rest.startswith("end"):
            job = rest.split()[1]
            if job == "scheduler" or job == "memcached":
                continue
            if job in job_status and job_status[job][0] == "running":
                start_sec = job_status[job][1]
                job_states[job].append((start_sec, t_sec))
            job_status.pop(job, None)

    # Sort jobs by first start time
    sorted_jobs = sorted(job_first_start_time.keys(), key=lambda j: job_first_start_time[j])[1:]

    # Assign a consistent color for each job
    colormap = cm.get_cmap('tab20', len(sorted_jobs))
    job_colors = {job: colormap(i) for i, job in enumerate(sorted_jobs)}

    # Plot
    yticks = []
    yticklabels = []

    for i, job in enumerate(sorted_jobs):
        color = job_colors[job]
        for start, end in job_states[job]:
            ax.barh(i, end - start, left=start, height=0.4, color=color)
        yticks.append(i)
        yticklabels.append(job)

    ax.set_yticks(yticks)
    ax.set_yticklabels(yticklabels)
    ax.set_xlabel("Time (seconds)")
    ax.set_title("Job Execution Timeline")
    
    ax.grid(True, which='both', axis='x', linestyle='--', alpha=0.5)
    ax.xaxis.set_ticks_position('top')
    ax.xaxis.set_label_position('top')
    ax.tick_params(axis='x', which='both', bottom=False, top=True, labeltop=True, labelbottom=False)

def plot_cpu_cored(ax, job_log_file):
    with open(job_log_file, "r") as f:
        lines = f.readlines()
    time_format = "%Y-%m-%dT%H:%M:%S.%f"
    timestamps = []
    for line in lines:
        if line.strip():
            ts_str = line.split(" ", 1)[0]
            timestamps.append(datetime.strptime(ts_str, time_format))
    T0 = min(timestamps)

    timestamps = []
    core_counts = []

    with open(job_log_file, 'r') as file:
        for line in file:
            if "updated_cores memcached" in line:
                # Extract timestamp
                time_str = line.split()[0]
                time_obj = datetime.strptime(time_str, time_format)
                t_sec = (time_obj - T0).total_seconds()

                # Extract list of cores from brackets
                match = re.search(r'\[([0-9,\s]+)\]', line)
                if match:
                    cores = [int(c.strip()) for c in match.group(1).split(',') if c.strip().isdigit()]
                    timestamps.append(t_sec)
                    core_counts.append(len(cores))

    # Plot without dots (no marker)
    ax.plot(timestamps, core_counts, drawstyle='steps-post', linewidth=2, label='memcached core count')
    ax.set_xlabel('Time (seconds)')
    ax.set_ylabel('Number of cores', color='tab:blue')
    ax.tick_params(axis='y', labelcolor='tab:blue')
    ax.set_title('Number of cores over Time')

def plot_mcperf_log_file(ax, log_file, job_log_file):
    # Read the log file, skipping the first two lines (for Timestamp start/end)
    with open(log_file, 'r') as f:
        lines = f.readlines()

    df = pd.read_csv(log_file, sep=r'\s+', header=2)
    df['Timestamp'] = df.index * 3

    # Create a second y-axis to plot QPS
    ax_twin = ax.twinx()
    ax_twin.plot(df['Timestamp'], df['QPS'], color='tab:green', label='QPS', linewidth=2)
    ax_twin.set_ylabel('QPS', color='tab:green')
    ax_twin.tick_params(axis='y', labelcolor='tab:green')

    ax.yaxis.set_visible(False)  # Hide y-axis ticks and labels
    ax.spines['left'].set_visible(False)  # Hide left spine (axis line)

    # Title and show the plot
    ax.set_title('QPS over Time')
    ax.set_xlabel('Time (seconds)')
    ax.grid(True, which='both', axis='x', linestyle='--', alpha=0.5)

if __name__ == "__main__":

    job_logs = ["task4_outfiles_3s/jobs_1.txt", "task4_outfiles_3s/jobs_2.txt", "task4_outfiles_3s/jobs_3.txt"]
    mcperf_logs = ["task4_outfiles_3s/mcperf_1.txt", "task4_outfiles_3s/mcperf_2.txt", "task4_outfiles_3s/mcperf_3.txt"]
    for idx, job_log_file in enumerate(job_logs):
        fig, (ax_top, ax_middle, ax_bottom) = plt.subplots(
            nrows=3, ncols=1, figsize=(12, 10), sharex=True, gridspec_kw={'height_ratios': [2, 1, 1]})

        plot_job_log_file(ax_top, job_log_file)
        plot_cpu_cored(ax_middle, job_log_file)
        plot_mcperf_log_file(ax_bottom, mcperf_logs[idx], job_log_file)

        plt.grid(True)
        plt.tight_layout()
        os.makedirs("part4_4", exist_ok=True) 
        plt.savefig(f"part4_4/plot_B{idx+1}.png")
