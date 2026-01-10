#!/bin/bash
# Test script for AI model evaluation
# Usage: ./test-model.sh <model-name>

MODEL=$1
OUTPUT_DIR="./reports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="${OUTPUT_DIR}/${MODEL//:/--}-${TIMESTAMP}.json"

if [ -z "$MODEL" ]; then
    echo "Usage: $0 <model-name>"
    echo "Example: $0 gemma3n:e2b"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "Testing model: $MODEL"
echo "Report will be saved to: $REPORT_FILE"
echo ""

# Test results array
declare -A results

# Function to test a prompt
test_prompt() {
    local test_name=$1
    local prompt=$2
    local expected=$3

    echo "Running test: $test_name"

    # Time the request
    start_time=$(date +%s.%N)

    response=$(curl -s http://localhost:11434/api/generate -d "{
        \"model\": \"$MODEL\",
        \"prompt\": \"$prompt\",
        \"stream\": false,
        \"options\": {
            \"temperature\": 0.7
        }
    }")

    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc)

    # Extract response text and metrics
    response_text=$(echo "$response" | jq -r '.response')
    total_duration=$(echo "$response" | jq -r '.total_duration')
    load_duration=$(echo "$response" | jq -r '.load_duration')
    eval_count=$(echo "$response" | jq -r '.eval_count')
    eval_duration=$(echo "$response" | jq -r '.eval_duration')

    # Calculate tokens/second
    if [ "$eval_duration" != "null" ] && [ "$eval_count" != "null" ]; then
        tokens_per_sec=$(echo "scale=2; $eval_count * 1000000000 / $eval_duration" | bc)
    else
        tokens_per_sec="N/A"
    fi

    echo "  Response: ${response_text:0:100}..."
    echo "  Duration: ${duration}s"
    echo "  Tokens/sec: $tokens_per_sec"
    echo ""

    # Store result
    results["$test_name"]=$(cat <<EOF
{
    "test_name": "$test_name",
    "prompt": $(echo "$prompt" | jq -Rs .),
    "response": $(echo "$response_text" | jq -Rs .),
    "expected": $(echo "$expected" | jq -Rs .),
    "duration_sec": $duration,
    "tokens_per_sec": "$tokens_per_sec",
    "eval_count": $eval_count,
    "total_duration_ns": $total_duration,
    "load_duration_ns": $load_duration
}
EOF
)
}

# Warm-up
echo "Warming up model..."
curl -s http://localhost:11434/api/generate -d "{
    \"model\": \"$MODEL\",
    \"prompt\": \"Hello\",
    \"stream\": false
}" > /dev/null
echo ""

# ============================================================
# DICTATION TESTS
# ============================================================

echo "=== DICTATION TESTS ==="
echo ""

# Test 1: Grammar Cleanup
test_prompt \
    "grammar_cleanup" \
    "Clean up this transcription, removing filler words and fixing grammar. Output only the cleaned text: so um basically i was thinking you know that we should like maybe consider uh doing something about the the website performance because its been really slow lately" \
    "Professional sentence without filler words"

# Test 2: Translation EN→PT-BR
test_prompt \
    "translation_en_pt" \
    "Translate to Brazilian Portuguese: The quarterly report shows a 15% increase in user engagement, primarily driven by our new mobile features." \
    "O relatório trimestral mostra um aumento de 15% no engajamento dos usuários, impulsionado principalmente por nossos novos recursos móveis."

# Test 3: Translation PT-BR→EN
test_prompt \
    "translation_pt_en" \
    "Translate to English: Precisamos agendar uma reunião para discutir os próximos passos do projeto de integração com a API." \
    "We need to schedule a meeting to discuss the next steps for the API integration project."

# Test 4: Tone: Casual to Formal
test_prompt \
    "tone_casual_to_formal" \
    "Rewrite this in a professional, formal tone: hey so the thing is we kinda need more time to finish this because stuff came up" \
    "Professional business communication"

# Test 5: Prompt Enhancement
test_prompt \
    "prompt_enhancement" \
    "Improve this vague prompt to be more specific and actionable: make the app faster" \
    "Specific, actionable prompt with context"

# Test 6: Code Dictation
test_prompt \
    "code_dictation" \
    "Convert this to a clean function description: create a function called fetch user data that takes a user ID parameter and returns a promise with the user object from the API endpoint slash users slash user ID" \
    "Clean, technical function description"

# ============================================================
# MEETING TESTS
# ============================================================

echo "=== MEETING TESTS ==="
echo ""

# Test 7: Summarization
test_prompt \
    "summarization" \
    "Summarize this meeting in 3-5 bullet points: John mentioned he'll have the designs ready by Friday. Sarah said she needs to review the legal docs before we can proceed. Mike will set up the demo environment tomorrow. We discussed the budget and agreed to allocate an extra 10k for marketing. The launch date is set for next month but we need to confirm with stakeholders first." \
    "Concise bullet points with key decisions"

# Test 8: Action Items Extraction
test_prompt \
    "action_items" \
    "Extract action items with owners and deadlines: John mentioned he'll have the designs ready by Friday. Sarah said she needs to review the legal docs before we can proceed. Mike will set up the demo environment tomorrow." \
    "Structured list with owner + task + deadline"

# Test 9: Tone/Sentiment Analysis
test_prompt \
    "sentiment_analysis" \
    "Analyze the tone and sentiment of this message: I'm concerned about the timeline. We've already pushed back twice and stakeholders are getting frustrated." \
    "Sentiment: Negative/Concerned, Urgency: High"

# ============================================================
# SAVE REPORT
# ============================================================

echo "Saving report to $REPORT_FILE"

# Build JSON report
cat > "$REPORT_FILE" <<EOF
{
    "model": "$MODEL",
    "timestamp": "$TIMESTAMP",
    "tests": [
EOF

first=true
for test_name in "${!results[@]}"; do
    if [ "$first" = true ]; then
        first=false
    else
        echo "," >> "$REPORT_FILE"
    fi
    echo "${results[$test_name]}" >> "$REPORT_FILE"
done

cat >> "$REPORT_FILE" <<EOF
    ]
}
EOF

echo ""
echo "✓ Test complete!"
echo "Report saved to: $REPORT_FILE"
echo ""
echo "To view results:"
echo "  cat $REPORT_FILE | jq ."
