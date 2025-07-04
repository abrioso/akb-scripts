#!/bin/bash

# Check if an argument (directory) was provided
if [ -z "$1" ]; then
  echo "Usage: $0 /path/to/directory"
  exit 1
fi

TARGET_DIR="$1"

# Check if the directory exists
if [ ! -d "$TARGET_DIR" ]; then
  echo "Error: '$TARGET_DIR' is not a valid directory."
  exit 1
fi

# Get absolute path
ABS_DIR="$(cd "$TARGET_DIR" && pwd)"

# Output file name
INDEX_FILE="$ABS_DIR/index.html"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  echo "Error: 'jq' is not installed. Please install it to escape special characters in URLs."
  exit 1
fi

# Create HTML header
cat > "$INDEX_FILE" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Index of $(basename "$ABS_DIR")</title>
  <style>
    body { font-family: Arial, sans-serif; }
    ul { list-style-type: none; padding-left: 0; }
    li { margin: 4px 0; }
  </style>
</head>
<body>
  <h1>Index of $(basename "$ABS_DIR")</h1>
  <ul>
EOF

# List files and directories
for entry in "$ABS_DIR"/*; do
  name=$(basename "$entry")
  # Skip the index.html file itself
  if [ "$name" = "index.html" ]; then
    continue
  fi
  # Escape special characters in URLs
  url=$(printf '%s' "$name" | jq -sRr @uri)
  echo "    <li><a href=\"$url\">$name</a></li>" >> "$INDEX_FILE"
done

# Close HTML structure
cat >> "$INDEX_FILE" <<EOF
  </ul>
</body>
</html>
EOF

echo "File '$INDEX_FILE' successfully created."
