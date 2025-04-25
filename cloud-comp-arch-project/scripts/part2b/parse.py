import os 
from collections import defaultdict
import matplotlib.pyplot as plt
import seaborn as sns 
import pandas as pd
import numpy as np
import re

def parse_line(line):
    match = re.match(r'(?:(\d+)m)?([\d.]+)s', line.strip())

    if not match:
        raise ValueError("Invalid time format")

    minutes = int(match.group(1)) if match.group(1) else 0
    seconds = float(match.group(2))

    return minutes * 60 + seconds

def parse_file(file_path):
    try:
        with open(file_path, 'r') as file:
            for line_number, line in enumerate(file, start=1):
                stripped_line = line.strip().split()
                if stripped_line and stripped_line[0] == "real":  # skip empty lines
                    temp = parse_line(stripped_line[1])
                    return float(temp)
    except FileNotFoundError:
        print(f"File not found: {file_path}")
    except Exception as e:
        print(f"An error occurred: {e}", file_path)


def plot_runtime_by_app_type(save_path, data_dict):
    # Flatten nested dict into records
    records = [
        {"app_type": app, "nr_threads": threads, "runtime": runtime}
        for app, thread_data in data_dict.items()
        for threads, runtime in thread_data.items()
    ]

    # Create DataFrame
    df = pd.DataFrame(records)
    df = df.sort_values(by=["app_type", "nr_threads"])

    # Plot with thread count as hue, app_type on x-axis
    plt.figure(figsize=(8, 5))
    sns.barplot(data=df, x="app_type", y="runtime", hue="nr_threads", palette="crest")

    plt.title("Runtime per App Type by Number of Threads")
    plt.xlabel("App Type")
    plt.ylabel("Runtime (s)")
    plt.legend(title="Threads")
    plt.tight_layout()    
    plt.savefig(save_path)


def get_oldest_folder():    
    return sorted([f for f in os.listdir("logs/part2b/")])[-1]

def main():
    LOGS = f"logs/part2b/{get_oldest_folder()}"
    
    parsed_measurements = defaultdict(lambda: defaultdict(float))

    for file_fname in os.listdir(LOGS):
        if file_fname != "res.png":
            file_name = os.path.splitext(file_fname)[0]
            _, file_name = file_name.split("-")
            app_type, thread_num = file_name.split("_") 

            parsed_measurements[app_type][thread_num] = parse_file(os.path.join(LOGS, file_fname))
    plot_runtime_by_app_type(os.path.join(LOGS, "res.png"), parsed_measurements)

if __name__ == "__main__":
    main()
