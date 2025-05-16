import matplotlib.pyplot as plt
from datetime import datetime
from collections import defaultdict
import matplotlib.cm as cm
import pandas as pd

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

def plot_mcperf_p95_qps(ax, log_file):
    df = pd.read_csv(log_file, sep=r'\s+', header=2)
    df['Timestamp'] = df.index * 10

    # Left y-axis: p95
    ax.axhline(y=800, color='r', linestyle='--', linewidth=1)
    ax.plot(df['Timestamp'], df['p95'], color='tab:blue', label='p95', linewidth=2)
    ax.set_ylabel('p95', color='tab:blue')
    ax.tick_params(axis='y', labelcolor='tab:blue')

    # Right y-axis: QPS
    ax_twin = ax.twinx()
    ax_twin.plot(df['Timestamp'], df['QPS'], color='tab:green', label='QPS', linewidth=2)
    ax_twin.set_ylabel('QPS', color='tab:green')
    ax_twin.tick_params(axis='y', labelcolor='tab:green')

    ax.set_xlabel('Time (seconds)')
    ax.grid(True, which='both', axis='x', linestyle='--', alpha=0.5)
    ax.set_title('p95 and QPS over Time')

if __name__ == "__main__":

    job_logs = ["task3_outfiles/jobs_1.txt", "task3_outfiles/jobs_2.txt", "task3_outfiles/jobs_3.txt"]
    mcperf_logs = ["task3_outfiles/mcperf_1.txt", "task3_outfiles/mcperf_2.txt", "task3_outfiles/mcperf_3.txt"]
    for idx, log_file in enumerate(job_logs):
        fig, (ax_top, ax_bottom) = plt.subplots(
            nrows=2, ncols=1, figsize=(12, 8), sharex=True, gridspec_kw={'height_ratios': [2, 1]})

        plot_job_log_file(ax_top, log_file)
        plot_mcperf_p95_qps(ax_bottom, mcperf_logs[idx])

        plt.tight_layout()
        plt.savefig(f"part4_3/plot_A{idx+1}.png")
