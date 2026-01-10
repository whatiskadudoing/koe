#!/bin/bash
# Generate comparison report from all test results

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORTS_DIR="$SCRIPT_DIR/reports"
OUTPUT_FILE="$SCRIPT_DIR/Model-Comparison-Report.md"

echo "Generating comparison report from test results..."
echo ""

# Start report
cat > "$OUTPUT_FILE" <<'EOF'
# AI Model Comparison Report

Auto-generated comparison of model performance across test categories.

## Test Categories

- **Grammar Cleanup**: Remove filler words, fix transcription errors
- **Translation**: EN↔PT-BR accuracy and fluency
- **Tone Adjustment**: Casual→Formal rewriting
- **Prompt Enhancement**: Improve vague prompts
- **Code Dictation**: Technical term accuracy
- **Summarization**: Meeting notes condensation
- **Action Items**: Task extraction (owner + deadline)
- **Sentiment Analysis**: Tone detection

---

EOF

# Function to extract metric from JSON
extract_metric() {
    local file=$1
    local test_name=$2
    local metric=$3

    jq -r ".tests[] | select(.test_name == \"$test_name\") | .$metric // \"N/A\"" "$file" 2>/dev/null
}

# Create comparison table
echo "## Performance Comparison" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "| Model | Avg Speed (tok/s) | Grammar | Translation EN-PT | Translation PT-EN | Tone | Prompt | Code |" >> "$OUTPUT_FILE"
echo "|-------|-------------------|---------|-------------------|-------------------|------|--------|------|" >> "$OUTPUT_FILE"

for report in "$REPORTS_DIR"/*.json; do
    if [ -f "$report" ]; then
        model=$(jq -r '.model' "$report")

        # Calculate average tokens/sec across all tests
        avg_speed=$(jq '[.tests[].tokens_per_sec | select(. != "N/A") | tonumber] | add / length' "$report" 2>/dev/null)
        avg_speed=$(printf "%.1f" "$avg_speed" 2>/dev/null || echo "N/A")

        # Extract test durations (shorter is better)
        grammar_dur=$(extract_metric "$report" "grammar_cleanup" "duration_sec")
        trans_en_pt_dur=$(extract_metric "$report" "translation_en_pt" "duration_sec")
        trans_pt_en_dur=$(extract_metric "$report" "translation_pt_en" "duration_sec")
        tone_dur=$(extract_metric "$report" "tone_casual_to_formal" "duration_sec")
        prompt_dur=$(extract_metric "$report" "prompt_enhancement" "duration_sec")
        code_dur=$(extract_metric "$report" "code_dictation" "duration_sec")

        # Format durations with 1 decimal place
        grammar_dur=$(printf "%.1fs" "$grammar_dur" 2>/dev/null || echo "N/A")
        trans_en_pt_dur=$(printf "%.1fs" "$trans_en_pt_dur" 2>/dev/null || echo "N/A")
        trans_pt_en_dur=$(printf "%.1fs" "$trans_pt_en_dur" 2>/dev/null || echo "N/A")
        tone_dur=$(printf "%.1fs" "$tone_dur" 2>/dev/null || echo "N/A")
        prompt_dur=$(printf "%.1fs" "$prompt_dur" 2>/dev/null || echo "N/A")
        code_dur=$(printf "%.1fs" "$code_dur" 2>/dev/null || echo "N/A")

        echo "| \`$model\` | $avg_speed | $grammar_dur | $trans_en_pt_dur | $trans_pt_en_dur | $tone_dur | $prompt_dur | $code_dur |" >> "$OUTPUT_FILE"
    fi
done

echo "" >> "$OUTPUT_FILE"
echo "---" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Add detailed test results
echo "## Detailed Test Results" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

for report in "$REPORTS_DIR"/*.json; do
    if [ -f "$report" ]; then
        model=$(jq -r '.model' "$report")
        timestamp=$(jq -r '.timestamp' "$report")

        echo "### \`$model\`" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        echo "**Test Date:** $timestamp" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"

        # Grammar Cleanup
        grammar_response=$(extract_metric "$report" "grammar_cleanup" "response")
        grammar_duration=$(extract_metric "$report" "grammar_cleanup" "duration_sec")
        grammar_tokens=$(extract_metric "$report" "grammar_cleanup" "tokens_per_sec")

        echo "#### Grammar Cleanup" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        echo "- **Response:** $grammar_response" >> "$OUTPUT_FILE"
        echo "- **Duration:** ${grammar_duration}s" >> "$OUTPUT_FILE"
        echo "- **Speed:** $grammar_tokens tok/s" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"

        # Translation EN→PT
        trans_en_pt_response=$(extract_metric "$report" "translation_en_pt" "response")
        trans_en_pt_duration=$(extract_metric "$report" "translation_en_pt" "duration_sec")
        trans_en_pt_tokens=$(extract_metric "$report" "translation_en_pt" "tokens_per_sec")

        echo "#### Translation (EN→PT-BR)" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        echo "- **Response:** $trans_en_pt_response" >> "$OUTPUT_FILE"
        echo "- **Duration:** ${trans_en_pt_duration}s" >> "$OUTPUT_FILE"
        echo "- **Speed:** $trans_en_pt_tokens tok/s" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"

        echo "---" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi
done

# Add summary statistics
echo "## Summary Statistics" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "Generated on: $(date)" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

num_models=$(ls -1 "$REPORTS_DIR"/*.json 2>/dev/null | wc -l)
echo "- **Models tested:** $num_models" >> "$OUTPUT_FILE"
echo "- **Test categories:** 9" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "✓ Comparison report generated: $OUTPUT_FILE"
cat "$OUTPUT_FILE"
