import argparse
import os
import json
from datetime import datetime, timezone
import statistics

def main(data_folder, num_runs):
    jobs = {}
    convert = lambda time: int(datetime.strptime(time, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp())
    total_durations = []

    for run in range(num_runs):
        filename = os.path.join(data_folder, f"results_{run}.json")
        with open(filename, "r") as f:
            results = json.load(f)

        start_times = []
        end_times = []
        for item in results["items"]:
            name = item["status"]["containerStatuses"][0]["name"]

            if str(name) != "memcached":
                start_time = item["status"]["containerStatuses"][0]["state"]["terminated"]["startedAt"]
                completion_time = item["status"]["containerStatuses"][0]["state"]["terminated"]["finishedAt"]

                name = name.split("-")[1]

                if name not in jobs:
                    jobs[name] = []

                start_times.append(convert(start_time))
                end_times.append(convert(completion_time))
                jobs[name].append(convert(completion_time) - convert(start_time))
        total_durations.append(max(end_times) - min(start_times))
    
    for job, times in jobs.items():
        print(f"{job}: {statistics.mean(times):.2f} ± {statistics.stdev(times):.2f}")
    print(f"Total duration: {statistics.mean(total_durations):.2f} ± {statistics.stdev(total_durations):.2f}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Plotting script")
    parser.add_argument("--data_folder", required=True, type=str, help="Path to the data folder")
    parser.add_argument("--num_runs", required=True, type=int, help="Number of runs")

    args = parser.parse_args()

    main(args.data_folder, args.num_runs)