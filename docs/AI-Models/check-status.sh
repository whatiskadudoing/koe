#!/bin/bash
# Quick status check for downloads and tests

echo "=== Model Downloads ==="
ollama list
echo ""

echo "=== Test Reports ==="
if [ -d "./reports" ]; then
    ls -lh ./reports/*.json 2>/dev/null | awk '{print $9, $5}' | sed 's/.*\///'
    echo ""
    echo "Total reports: $(ls -1 ./reports/*.json 2>/dev/null | wc -l)"
else
    echo "No reports yet"
fi
echo ""

echo "=== Quick Performance Summary ==="
for report in ./reports/*.json; do
    if [ -f "$report" ]; then
        model=$(jq -r '.model' "$report")
        avg_speed=$(jq '[.tests[].tokens_per_sec | select(. != "N/A") | tonumber] | add / length' "$report" 2>/dev/null)
        avg_speed=$(printf "%.1f" "$avg_speed" 2>/dev/null || echo "N/A")
        echo "$model: $avg_speed tok/s"
    fi
done
