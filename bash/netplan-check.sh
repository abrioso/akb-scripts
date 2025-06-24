#!/bin/bash

# Script to validate and correct netplan YAML files

# Check if a file is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <netplan-file.yaml>"
    exit 1
fi

FILE=$1

# Validate YAML syntax
echo "Validating YAML syntax..."
if ! yamllint "$FILE" 2>&1 | tee /tmp/yamllint_output; then
    echo "YAML syntax errors detected. Please review the following suggestions:"
    cat /tmp/yamllint_output
    exit 1
fi


# Test netplan configuration
echo "Testing netplan configuration..."
if ! sudo netplan try; then
    echo "Netplan configuration test failed. Please review the file."
    exit 1
fi

echo "Netplan configuration is valid."

# Apply netplan configuration
echo "Applying netplan configuration..."
if sudo netplan apply; then
    echo "Netplan configuration applied successfully."
else
    echo "Failed to apply netplan configuration."
    exit 1
fi
