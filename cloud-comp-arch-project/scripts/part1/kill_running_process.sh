#/bin/sh

# Check if the user provided the executable name
if [ -z "$1" ]; then
  echo "Usage: $0 <executable_name>"
  exit 1
fi

# Get the PID(s) of the executable
PIDS=$(pgrep "$1")

# Check if the process is running
if [ -z "$PIDS" ]; then
  echo "No process found with name: $1"
  exit 1
fi

# Kill the process(es)
echo "Killing process(es) with name: $1"
echo "$PIDS" | xargs kill

# Optional: Confirm the kill
if [ $? -eq 0 ]; then
  echo "Process(es) killed successfully."
else
  echo "Failed to kill process(es)."
fi
