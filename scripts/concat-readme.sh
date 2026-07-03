#!/bin/bash

################################################################################
# Script: concat-readme.sh
# Description: Concatenates Requirements.md, Architecture.md, and Steps.md
#              into a single README.md file with a title header.
# Usage: ./scripts/concat-readme.sh
################################################################################

set -e  # Exit immediately if a command exits with a non-zero status

# Define the output file
OUTPUT_FILE="README.md"

# Define the source files in the order they should be concatenated
SOURCE_FILES=(
    "Requirements.md"
    "Architecture.md"
    "Steps.md"
)

echo "Starting README.md generation..."

# Create or overwrite the README.md file with the title header
echo "# Semantic Code Searcher" > "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Iterate through each source file and append its contents
for file in "${SOURCE_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "Adding contents from $file..."
        
        # Add a blank line for spacing between files
        echo "" >> "$OUTPUT_FILE"
        
        # Append the file contents
        cat "$file" >> "$OUTPUT_FILE"
        
        # Add another blank line after the file contents
        echo "" >> "$OUTPUT_FILE"
    else
        echo "Warning: $file not found, skipping..."
    fi
done

echo "README.md has been successfully generated!"
echo "Output file: $OUTPUT_FILE"

# Made with Bob
