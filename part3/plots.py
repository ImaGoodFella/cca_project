import pandas as pd
import matplotlib.pyplot as plt 

import os
import argparse
import json
from datetime import datetime, timezone
import statistics


colors = {
    "blackscholes": "#cca000",
    "canneal": "#ccccaa",
    "dedup": "#ccacca",
    "ferret": "#aaccca",
    "freqmine": "#0cca00",
    "radix": "#00cca0",
    "vips": "#cc0a00",
}

machines = {
    "node-a-2core": "e2-highmem-2",
    "node-b-2core": "n2-highcpu-2",
    "node-c-4core": "c3-highcpu-4",
    "node-d-4core": "n2-standard-4",
}

def main(data_folder, num_runs):
    for run in range(1, num_runs + 1, 1):
        latency_df = pd.read_csv(
            os.path.join(data_folder, f"mcperf_{run}.txt"),
            sep=r"\s+",
            engine="python",
            skipfooter=1,
        )

        latency_df["ts_start"] /= 1000
        latency_df["ts_end"] /= 1000
        latency_df["duration"] = latency_df["ts_end"] - latency_df["ts_start"]
        
        with open(os.path.join(data_folder, f"pods_{run}.json"), "r") as f:
            results = json.load(f)
        
        times = {}
        convert = lambda time: int(datetime.strptime(time, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp())

        for item in results["items"]:
            name = item["status"]["containerStatuses"][0]["name"]

            if str(name) != "memcached":
                start_time = item["status"]["containerStatuses"][0]["state"]["terminated"]["startedAt"]
                completion_time = item["status"]["containerStatuses"][0]["state"]["terminated"]["finishedAt"]
                node = item["spec"]["nodeSelector"]["cca-project-nodetype"]

                name = name.split("-")[1]

                times[name] = {
                    "start_time": convert(start_time),
                    "completion_time": convert(completion_time),
                    "node": node,
                }
        
        global_start = min([times[name]["start_time"] for name in times])
        global_duration = max([times[job]["completion_time"] for job in times]) - global_start
        global_duration = round(global_duration / 100) * 100
        latency_df["ts_start"] -= global_start
        latency_df["ts_end"] -= global_start

        latency_df = latency_df[latency_df["ts_end"] > 0]

        fig, (ax1, ax2) = plt.subplots(nrows=2, figsize=(10, 8), sharex=True, gridspec_kw={'height_ratios': [2, 1]})

        for i, row in latency_df.iterrows():
            ax1.bar(
                x=row["ts_start"],
                height=row["p95"],
                width=row["duration"],
                color="#eeeeee",
                edgecolor="black",
                align="edge",
            )

        slo = 1000
        ax1.axhline(
            y=slo,
            color="red",
            linestyle="--",
            linewidth=1,
        )      
        ax1.annotate(
            'SLO',
            xy=(statistics.mean(ax1.get_xlim()), slo),
            xytext=(0, 5),
            textcoords='offset points',
            ha='right',
            va='bottom',
            fontsize=10,
            color="red",
        )

        ax1.set_title(f"Memcached p95 Latency (above), Jobs Timeline (below)", fontweight="bold")
        
        ax1.set_xlabel("Time (s)")
        ax1.set_xticks(range(0, global_duration + 1, 10))
        ax1.set_xticklabels(range(0, global_duration + 1, 10))

        ax1.set_yticks(range(0, 1200 + 1, 200))
        ax1.set_ylabel(r"Latency ($\mu$s)")
        ax1.set_ylim(0, 1500)

        ax1.grid(visible=True, axis="y")

        nodes = sorted(set([times[job]["node"] for job in times]))
        nodes_pos = {node: i for i, node in enumerate(nodes)}

        for job in times:
            job_start = times[job]["start_time"] - global_start
            job_end = times[job]["completion_time"] - global_start
            job_color = colors[job]
            job_node = times[job]["node"]

            ax2.hlines(
                y=nodes_pos[job_node],
                xmin=job_start,
                xmax=job_end,
                color=job_color,
                linewidth=1,
            )

            ax2.plot(job_start, nodes_pos[job_node], marker="o", color=job_color, markersize=10)
            ax2.plot(job_end, nodes_pos[job_node], marker="x", color=job_color, markersize=10, markeredgewidth=2)


        ax2.set_xlabel("Time (s)")
        ax2.set_xticks(range(0, global_duration + 1, 10))
        ax2.set_xticklabels(range(0, global_duration + 1, 10))

        ax2.set_ylabel("Machine")
        ax2.set_yticks(range(len(nodes)))
        ax2.set_yticklabels(nodes)

        ax2.grid(visible=True, axis="x")

        plt.savefig(f"run_{run}.png", dpi=300, bbox_inches="tight")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Plotting script")

    parser.add_argument("--data_folder", required=True, type=str, help="Path to the data folder")
    parser.add_argument("--num_runs", required=True, type=int, help="Number of runs")

    args = parser.parse_args()

    main(args.data_folder, args.num_runs)