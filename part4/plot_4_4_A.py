import matplotlib.pyplot as plt
from datetime import datetime
from collections import defaultdict
import matplotlib.cm as cm
import pandas as pd
import os

def plot_job_log_file(ax, log_file):
    with open(log_file, "r") as f:
        lines = f.readlines()

    job_states = defaultdict(list)
    job_status = {}
    job_first_start_time = {}
    time_format = "%Y-%m-%dT%H:%M:%S.%f"

    timestamps = []
    for line in lines:
        if line.strip():
            ts_str = line.split(" ", 1)[0]
            timestamps.append(datetime.strptime(ts_str, time_format))
    T0 = min(timestamps)

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

    sorted_jobs = sorted(job_first_start_time.keys(), key=lambda j: job_first_start_time[j])[1:]
    colormap = cm.get_cmap('tab20', len(sorted_jobs))
    job_colors = {job: colormap(i) for i, job in enumerate(sorted_jobs)}

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

def plot_mcperf_split(ax_p95, ax_qps, log_file):
    df = pd.read_csv(log_file, sep=r'\s+', header=2)
    df['Timestamp'] = df.index * 3

    # P95
    ax_p95.axhline(y=800, color='r', linestyle='--', linewidth=1)
    ax_p95.plot(df['Timestamp'], df['p95'], color='tab:blue', linewidth=2)
    ax_p95.set_ylabel('p95 latency (μs)', color='tab:blue')
    ax_p95.set_title('Memcached p95 latency over Time')
    ax_p95.tick_params(axis='y', labelcolor='tab:blue')
    ax_p95.grid(True, linestyle='--', alpha=0.5)

    # QPS (y-axis on the right)
    ax_qps.spines['right'].set_position(('outward', 0))
    ax_qps.yaxis.set_label_position('right')
    ax_qps.yaxis.tick_right()
    ax_qps.plot(df['Timestamp'], df['QPS'], color='tab:green', linewidth=2)
    ax_qps.set_ylabel('QPS', color='tab:green')
    ax_qps.set_xlabel('Time (seconds)')
    ax_qps.set_title('Memcached QPS over Time')
    ax_qps.tick_params(axis='y', labelcolor='tab:green')
    ax_qps.grid(True, linestyle='--', alpha=0.5)

if __name__ == "__main__":
    job_logs = ["task4_outfiles_3s/jobs_1.txt", "task4_outfiles_3s/jobs_2.txt", "task4_outfiles_3s/jobs_3.txt"]
    mcperf_logs = ["task4_outfiles_3s/mcperf_1.txt", "task4_outfiles_3s/mcperf_2.txt", "task4_outfiles_3s/mcperf_3.txt"]

    os.makedirs("part4_4", exist_ok=True)

    for idx, log_file in enumerate(job_logs):
        fig, (ax_top, ax_mid, ax_bottom) = plt.subplots(
            nrows=3, ncols=1, figsize=(12, 10), sharex=True,
            gridspec_kw={'height_ratios': [2, 1, 1]}
        )

        plot_job_log_file(ax_top, log_file)
        plot_mcperf_split(ax_mid, ax_bottom, mcperf_logs[idx])

        plt.tight_layout()
        plt.savefig(f"part4_4/plot_A{idx+1}.png")
