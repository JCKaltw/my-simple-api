#!/bin/bash

# Check if create_api.sh.run-progress.txt file exists
if [ ! -f "create_api.sh.run-progress.txt" ]; then
  echo "Error: create_api.sh.run-progress.txt file not found."
  exit 1
fi

# Read the run-progress file in reverse order
while read -r line; do
  # Extract the token and comment from the line
  token=$(echo "$line" | cut -d' ' -f1)
  comment=$(echo "$line" | cut -d' ' -f2-)

  echo "Token: $token"
  echo "Comment: $comment"

  # Exit the loop after processing the first token
  break
done < <(tail -r "create_api.sh.run-progress.txt")

echo "Cleanup completed successfully."