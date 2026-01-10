#!/bin/bash
# Run tests for all installed models and generate comparison report

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_SCRIPT="$SCRIPT_DIR/test-model.sh"
REPORTS_DIR="$SCRIPT_DIR/reports"

# Models to test
MODELS=(
    # Dictation - Fast
    "gemma3n:e2b"
    "phi4-mini"
    "qwen3:4b"

    # Dictation - Balanced
    "mistral:7b"
    "qwen2.5:7b"
    "qwen3:8b"
    "deepseek-r1:8b"

    # Dictation - Quality
    "phi4:14b"
    "gemma3:12b"

    # Meeting - Summarization
    "qwen3:30b-a3b"
)

echo "================================================"
echo "  AI Model Test Suite"
echo "================================================"
echo ""
echo "This will test all installed models."
echo "Each test takes ~2-5 minutes depending on model speed."
echo ""

# Check which models are installed
echo "Checking installed models..."
INSTALLED_MODELS=$(ollama list | tail -n +2 | awk '{print $1}')
echo ""

TESTS_RUN=0
TESTS_SKIPPED=0

for model in "${MODELS[@]}"; do
    if echo "$INSTALLED_MODELS" | grep -q "^${model}"; then
        echo "✓ Testing $model..."
        "$TEST_SCRIPT" "$model"
        TESTS_RUN=$((TESTS_RUN + 1))
        echo ""
    else
        echo "⊘ Skipping $model (not installed)"
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    fi
done

echo ""
echo "================================================"
echo "  Test Summary"
echo "================================================"
echo "Tests run: $TESTS_RUN"
echo "Tests skipped: $TESTS_SKIPPED"
echo "Reports saved to: $REPORTS_DIR"
echo ""
echo "To view all reports:"
echo "  ls -lh $REPORTS_DIR"
echo ""
echo "To compare results:"
echo "  ./generate-comparison.sh"
