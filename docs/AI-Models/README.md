# AI Model Testing Suite

Automated testing framework for evaluating LLM models for Koe's dictation and meeting features.

## Overview

This directory contains:
- **Test plan** (`AI-Model-Test-Plan.md`) - Comprehensive testing strategy
- **Test scripts** - Automated test execution
- **Reports** - Test results and comparisons

## Quick Start

### 1. Download Models

Download models one at a time or in batches:

```bash
# Phase 1: Fast models (recommended to start)
ollama pull gemma3n:e2b      # 2GB - Edge-first, very fast
ollama pull phi4-mini        # 2.5GB - Math/logic focused
ollama pull qwen3:4b         # 2.5GB - Think mode capable

# Phase 2: Balanced models
ollama pull qwen3:8b         # 5GB - Think mode, 25 tok/s
ollama pull deepseek-r1:8b   # 5GB - Reasoning focused

# Phase 3: Summarization models
ollama pull qwen3:30b-a3b    # 4GB active - MoE, long context
ollama pull gemma3:12b       # 8GB - Long context

# Phase 4: Embedding models
ollama pull nomic-embed-text      # 548MB
ollama pull mxbai-embed-large     # 1.3GB
```

### 2. Test a Single Model

```bash
cd docs/AI-Models
./test-model.sh gemma3n:e2b
```

This runs 9 test categories:
- Grammar cleanup
- Translation (EN↔PT-BR)
- Tone adjustment
- Prompt enhancement
- Code dictation
- Summarization
- Action items extraction
- Sentiment analysis

### 3. Test All Installed Models

```bash
./run-all-tests.sh
```

This automatically:
- Detects which models are installed
- Runs all tests for each model
- Saves individual JSON reports to `reports/`

### 4. Generate Comparison Report

```bash
./generate-comparison.sh
```

Creates `Model-Comparison-Report.md` with:
- Performance comparison table (speed, accuracy)
- Detailed results for each model
- Summary statistics

## Test Results

Reports are saved to `reports/` in JSON format:

```json
{
  "model": "gemma3n:e2b",
  "timestamp": "20260110_143022",
  "tests": [
    {
      "test_name": "grammar_cleanup",
      "prompt": "...",
      "response": "...",
      "duration_sec": 1.23,
      "tokens_per_sec": "42.5",
      "eval_count": 52
    }
  ]
}
```

## Interpreting Results

### Speed Benchmarks (M1/M2/M3 Macs)

| Speed | Tokens/sec | User Experience |
|-------|------------|-----------------|
| **Very Fast** | >30 tok/s | Instant, real-time feel |
| **Fast** | 20-30 tok/s | Smooth, barely noticeable |
| **Medium** | 10-20 tok/s | Acceptable delay |
| **Slow** | <10 tok/s | Noticeable wait |

### Quality Metrics

- **Grammar Cleanup**: Should remove all filler words (um, uh, like, you know)
- **Translation**: Must be fluent and accurate, no hallucinations
- **Tone**: Appropriate formality level shift
- **Summarization**: Key points captured, no critical info lost
- **Action Items**: 95%+ precision on owner + task + deadline

## Model Selection Guide

### For Dictation Feature

**Fast Mode (Real-time)**
- `gemma3n:e2b` - Best for edge devices, 15% faster
- `phi4-mini` - Good for math/technical dictation
- `qwen3:4b` - Balanced, think mode available

**Quality Mode**
- `qwen3:8b` - Best balance of speed/quality
- `deepseek-r1:8b` - Best for complex reasoning
- `phi4:14b` - Best for mathematical content

### For Meeting Feature

**Summarization**
- `qwen3:30b-a3b` - MoE, 256K context, best for long meetings
- `gemma3:12b` - Good for standard meetings

**Search (Embeddings)**
- `qwen3-embedding:8b` - Multilingual, instruction-aware
- `nomic-embed-text` - Fast, 8K context
- `mxbai-embed-large` - Best MTEB score

## Continuous Testing

As new models are released:

1. Add model to `run-all-tests.sh`
2. Download: `ollama pull <model>`
3. Test: `./test-model.sh <model>`
4. Compare: `./generate-comparison.sh`
5. Document findings in audit report

## Troubleshooting

### Model not loading
```bash
ollama list  # Check if downloaded
ollama pull <model>  # Re-download if needed
```

### Slow responses
- First run is slower (model loading)
- Run warm-up: `ollama run <model> "Hello"`
- Check system resources: Activity Monitor → Memory/CPU

### Test script errors
```bash
# Make scripts executable
chmod +x *.sh

# Check jq is installed (for JSON parsing)
brew install jq
```

## Sources

- [Gemma 3n Developer Guide](https://developers.googleblog.com/en/introducing-gemma-3n-developer-guide/)
- [Qwen 3 Official Blog](https://qwenlm.github.io/blog/qwen3/)
- [DeepSeek R1 Paper](https://arxiv.org/pdf/2501.12948)
- [Embedding Models Benchmark](https://supermemory.ai/blog/best-open-source-embedding-models-benchmarked-and-ranked/)
- [Phi-4 vs Gemma 3 Comparison](https://llm-stats.com/models/compare/gemma-3-4b-it-vs-phi-4-mini)
