import matplotlib.pyplot as plt 
import numpy as np
import pandas as pd
import json
import sys
from datetime import datetime
from collections import defaultdict

def parse_time_return(json_path):
    parsed_data = defaultdict(float)

    time_format = '%Y-%m-%dT%H:%M:%SZ'
    file = open(json_path, 'r')
    json_file = json.load(file)

    for item in json_file['items']:
        name = item['status']["containerStatuses"][0]['name']
        if str(name) != "memcached":
            try:
                start_time = datetime.strptime(
                        item['status']['containerStatuses'][0]['state']['terminated']['startedAt'],
                        time_format)
                completion_time = datetime.strptime(
                        item['status']['containerStatuses'][0]['state']['terminated']['finishedAt'],
                        time_format)
                parsed_data[name] = (completion_time - start_time).total_seconds()
            except KeyError:
                print("Job {0} has not completed....".format(name))
                sys.exit(0)
    return parsed_data


def parse_time_not_return(json_path, parsed_data):

    time_format = '%Y-%m-%dT%H:%M:%SZ'
    file = open(json_path, 'r')
    json_file = json.load(file)
    
    start_times = []
    completion_times = []
    for item in json_file['items']:
        name = item['status']["containerStatuses"][0]['name']
        if str(name) != "memcached":
            try:
                start_time = datetime.strptime(
                        item['status']['containerStatuses'][0]['state']['terminated']['startedAt'],
                        time_format)
                completion_time = datetime.strptime(
                        item['status']['containerStatuses'][0]['state']['terminated']['finishedAt'],
                        time_format)
                start_times.append(start_time)
                completion_times.append(completion_time)
                parsed_data[name].append((completion_time - start_time).total_seconds())
            except KeyError:
                print("Job {0} has not completed....".format(name))
                sys.exit(0)
    parsed_data["total"].append((max(completion_times) - min(start_times)).total_seconds())
    return parsed_data


def parse_mcperf_log(file_path):
    parsed_file = []
    try:
        with open(file_path, 'r') as file:
            for line_number, line in enumerate(file, start=1):
                stripped_line = line.strip()
                if stripped_line and stripped_line.startswith("read"):  # skip empty lines
                    parsed_file.append(float(stripped_line.split()[-8]))
    except FileNotFoundError:
        print(f"File not found: {file_path}")
    except Exception as e:
        print(f"An error occurred: {e}")

    print(parsed_file)
    return parsed_file


def plot_latency_vs_time(data, file_name):
    plt.figure(figsize=(10, 6))

    indices = [i*10 for i in range(len(data))]
    plt.bar(indices, data, color='skyblue')
    plt.xlabel("Time (s)")
    plt.ylabel("Latency (us)")
    plt.title("Latency vs Time")

    plt.xticks(indices)

    plt.grid(axis='y', linestyle='--', alpha=0.7)

    plt.savefig(f"{file_name}.png")


def plot_parsec_jobs(data, file_name):
    labels = list(data.keys())
    values = list(data.values())

    plt.figure(figsize=(13, 9))
    colors = ["red", "mediumaquamarine", "green", "cyan", "pink", "beige", "olive"]
    plt.barh(labels, values, color=colors, height=0.4)
    plt.xlabel('Time (seconds)')
    plt.ylabel('Parsec job')
    plt.title('Job vs Time (seconds)')
    plt.grid(axis='x', linestyle='--', alpha=0.7)
    plt.savefig(f"{file_name}.png")


def main():
    MCPERF_LOG = "logs/part3/2025_04_30_17_28_44/mcperf.txt"

    mcperf_1 = parse_mcperf_log("logs/part3/2025_04_30_17_38_44/mcperf.txt")
    mcperf_2 = parse_mcperf_log("logs/part3/2025_04_30_18_00_59/mcperf.txt")
    mcperf_3 = parse_mcperf_log("logs/part3/2025_04_30_18_24_03/mcperf.txt")

    plot_latency_vs_time(mcperf_1, "mcperf_log_1")
    plot_latency_vs_time(mcperf_2, "mcperf_log_2")
    plot_latency_vs_time(mcperf_3, "mcperf_log_3")
    

    parsed_time = defaultdict(list)
    for idx, PODS_LOG in enumerate(["logs/part3/2025_04_30_17_38_44/results.json", "logs/part3/2025_04_30_18_00_59/results.json", "logs/part3/2025_04_30_18_24_03/results.json"]):
        parsed_data = parse_time_return(PODS_LOG)
        plot_parsec_jobs(parsed_data, f"results_{idx}")
        parse_time_not_return(PODS_LOG, parsed_time)

    res = {}
    for key, values in parsed_time.items():
        res[key] = (np.mean(values), np.std(values, ddof=1))
        print(key, res[key])

    print(res)

if __name__ == "__main__":
    main()
