import os 
from collections import defaultdict
import matplotlib.pyplot as plt
import numpy as np

def parse_line(line):
    line = line.split()
    return (line[-1], line[-6])

def parse_file(file_path):
    parsed_file = defaultdict(list)
    try:
        with open(file_path, 'r') as file:
            for line_number, line in enumerate(file, start=1):
                stripped_line = line.strip()
                if stripped_line and line_number > 1 and line_number < 18:  # skip empty lines
                    parsed = parse_line(stripped_line)
                    parsed_file[parsed[0]] = parsed[1]
    except FileNotFoundError:
        print(f"File not found: {file_path}")
    except Exception as e:
        print(f"An error occurred: {e}")

    return parsed_file


def plot_latency_vs_qps(path, data):
    plt.figure(figsize=(10, 6))

    for interference_type, qps_data in data.items():
        qps_values = sorted(qps_data.keys(), key=lambda x: int(x))
        avg_latencies = []
        std_devs = []

        for qps in qps_values:
            latencies = qps_data[qps]
            temp = []
            for lat in latencies:
                temp.append(float(lat))
            avg_latencies.append(np.mean(temp))
            std_devs.append(np.std(temp))

        plt.errorbar(
            qps_values,
            avg_latencies,
            yerr=std_devs,
            label=interference_type,
            marker='o',
            capsize=5
        )

    plt.xlabel("QPS")
    plt.ylabel("Latency (us)")
    plt.title("Latency vs QPS for Different Interference Types")
    plt.legend()
    plt.grid(True)
    plt.tight_layout()
    plt.savefig(os.path.join(path, "res.png"))


def get_oldest_folder():    
    return sorted([f for f in os.listdir("logs/part1/")])[-1]

def main():
    oldest_exp = get_oldest_folder()
    LOGS = f"logs/part1/{oldest_exp}"
    
    parsed_measurements = defaultdict(lambda: defaultdict(list))

    for file_fname in os.listdir(LOGS):
        file_name = os.path.splitext(file_fname)[0]
        server_type, interference_type, repetition = file_name.split("_")
        if server_type == "measure":
            parsed_file = parse_file(os.path.join(LOGS, file_fname))

            for qps, laten in parsed_file.items():
                parsed_measurements[interference_type][qps].append(laten)

    plot_latency_vs_qps(LOGS, parsed_measurements)

if __name__ == "__main__":
    main()
