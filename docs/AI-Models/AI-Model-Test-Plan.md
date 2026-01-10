# AI Model Test Plan for Koe

## Overview

Systematic testing of LLM models for two use cases:
1. **Dictation Feature** - Text improvement, translation, prompt enhancement
2. **Meeting Feature** - Summarization, tone analysis, search, tagging

## Test Categories

### Dictation Tests

| Test | Description | Metrics |
|------|-------------|---------|
| **Grammar Cleanup** | Fix transcription errors, filler words | Accuracy, naturalness |
| **Translation** | Translate to/from multiple languages | Accuracy, fluency |
| **Tone Adjustment** | Formal/casual/professional rewrite | Appropriateness |
| **Prompt Enhancement** | Improve vague instructions | Clarity, specificity |
| **Code Dictation** | Technical terms, code snippets | Accuracy of technical terms |
| **Speed Test** | Tokens/second on M1/M2/M3 | Performance |

### Meeting Tests

| Test | Description | Metrics |
|------|-------------|---------|
| **Summarization** | Condense 30min meeting to key points | Coverage, conciseness |
| **Action Items** | Extract tasks and owners | Precision, recall |
| **Tone Analysis** | Detect sentiment, urgency | Accuracy |
| **Topic Tagging** | Auto-tag meeting topics | Relevance |
| **Q&A Search** | Answer questions about meeting content | Accuracy |

### Embedding Tests (for Meeting Search)

| Test | Description | Metrics |
|------|-------------|---------|
| **Semantic Similarity** | Find related meeting segments | Precision@K |
| **Cross-lingual** | Search across languages | Accuracy |
| **Speed** | Embedding generation time | ms/1000 tokens |

---

## Models to Test

### Tier 1: Dictation - Fast (2-4GB RAM)

| Model | Size | Strengths | Priority |
|-------|------|-----------|----------|
| `gemma3n:e2b` | 2GB | Edge-first, 15% faster (Aug 2025), multimodal | HIGH |
| `phi4-mini` | 2.5GB | Math/logic, structured output | HIGH |
| `smollm2:1.7b` | 1GB | Smallest, fastest | MEDIUM |
| `qwen3:4b` | 2.5GB | Think mode, rivals 72B on some tasks | HIGH |

### Tier 2: Dictation - Balanced (4-8GB RAM)

| Model | Size | Strengths | Priority |
|-------|------|-----------|----------|
| `mistral:7b` | 4.4GB | Already installed, translation baseline | HIGH |
| `qwen2.5:7b` | 4.7GB | Already installed, general baseline | HIGH |
| `qwen3:8b` | 5GB | 25 tok/s on laptop, think mode | HIGH |
| `deepseek-r1:8b` | 5GB | Chain-of-thought reasoning, AIME 50% | MEDIUM |

### Tier 3: Dictation - Quality (8-16GB RAM)

| Model | Size | Strengths | Priority |
|-------|------|-----------|----------|
| `phi4:14b` | 8GB | Best math/logic at size | LOW |
| `gemma3:12b` | 8GB | Long context, multimodal | LOW |

### Tier 4: Meeting - Summarization (4-20GB RAM)

| Model | Size | Strengths | Priority |
|-------|------|-----------|----------|
| `qwen3:30b-a3b` | 4GB (active) | MoE, 256K context, rivals QwQ-32B | HIGH |
| `gemma3:12b` | 8GB | Long context summarization | MEDIUM |

### Tier 5: Embeddings (for Meeting Search)

| Model | Size | Strengths | Priority |
|-------|------|-----------|----------|
| `nomic-embed-text` | 548MB | 8K context, very fast | HIGH |
| `mxbai-embed-large` | 1.3GB | Best MTEB score 64.68 | MEDIUM |
| `qwen3-embedding:0.6b` | 600MB | Multilingual, instruction-aware | HIGH |

---

## Test Prompts

### Dictation Test Cases

#### 1. Grammar Cleanup
```
Input: "so um basically i was thinking you know that we should like maybe consider uh doing something about the the website performance because its been really slow lately"

Expected: Clean, professional sentence without filler words.
```

#### 2. Translation (EN→PT-BR)
```
Input: "The quarterly report shows a 15% increase in user engagement, primarily driven by our new mobile features."

Expected: Accurate Portuguese translation with correct technical terms.
```

#### 3. Translation (PT-BR→EN)
```
Input: "Precisamos agendar uma reunião para discutir os próximos passos do projeto de integração com a API."

Expected: Natural English translation.
```

#### 4. Tone: Casual to Formal
```
Input: "hey so the thing is we kinda need more time to finish this because stuff came up"

Expected: Professional business communication.
```

#### 5. Prompt Enhancement
```
Input: "make the app faster"

Expected: Specific, actionable prompt with context.
```

#### 6. Code Dictation
```
Input: "create a function called fetch user data that takes a user ID parameter and returns a promise with the user object from the API endpoint slash users slash user ID"

Expected: Clean function description or actual code.
```

### Meeting Test Cases

#### 1. Summarization
```
Input: [30-minute meeting transcript about product launch]

Expected: 3-5 bullet points covering key decisions, action items, deadlines.
```

#### 2. Action Items Extraction
```
Input: "John mentioned he'll have the designs ready by Friday. Sarah said she needs to review the legal docs before we can proceed. Mike will set up the demo environment tomorrow."

Expected: Structured list with owner + task + deadline.
```

#### 3. Tone/Sentiment Analysis
```
Input: "I'm concerned about the timeline. We've already pushed back twice and stakeholders are getting frustrated."

Expected: Sentiment: Negative/Concerned, Urgency: High
```

#### 4. Topic Tagging
```
Input: [Meeting transcript discussing budget, hiring, and Q4 goals]

Expected: Tags: #budget #hiring #q4-planning #goals
```

---

## Testing Procedure

### For Each Model:

1. **Download**
   ```bash
   ollama pull <model-name>
   ```

2. **Warm-up** (first run is slower due to loading)
   ```bash
   ollama run <model-name> "Hello"
   ```

3. **Run Tests** with timing
   ```bash
   time curl -s http://localhost:11434/api/generate -d '{
     "model": "<model-name>",
     "prompt": "<test-prompt>",
     "stream": false
   }' | jq -r '.response'
   ```

4. **Record Metrics**
   - Response quality (1-5 scale)
   - Response time
   - Token count (from API response)
   - Tokens/second

5. **Generate Report**
   - Save to `/docs/AI-Models/<Model>-Audit-Report.md`

---

## Download Order

### Phase 1: Fast Models (Small, Quick Tests)
```bash
ollama pull gemma3n:e2b      # 2GB - Edge-first, very fast
ollama pull phi4-mini        # 2.5GB - Math/logic focused
ollama pull qwen3:4b         # 2.5GB - Think mode capable
```

### Phase 2: Balanced Models
```bash
ollama pull qwen3:8b         # 5GB - Think mode, 25 tok/s
ollama pull deepseek-r1:8b   # 5GB - Reasoning focused
```

### Phase 3: Summarization Models
```bash
ollama pull qwen3:30b-a3b    # 4GB active - MoE, long context
ollama pull gemma3:12b       # 8GB - Long context
```

### Phase 4: Embedding Models
```bash
ollama pull nomic-embed-text      # 548MB
ollama pull mxbai-embed-large     # 1.3GB
```

---

## Success Criteria

### Dictation Feature
- **Speed**: >15 tok/s for real-time feel
- **Grammar**: 90%+ error correction
- **Translation**: Fluent, accurate
- **Prompt Enhancement**: Clear improvement in specificity

### Meeting Feature
- **Summarization**: Key points captured, no hallucination
- **Action Items**: 95%+ precision on extraction
- **Search**: Relevant results in top 3

---

## Sources

- [Gemma 3n Developer Guide](https://developers.googleblog.com/en/introducing-gemma-3n-developer-guide/)
- [Qwen 3 Official Blog](https://qwenlm.github.io/blog/qwen3/)
- [DeepSeek R1 Paper](https://arxiv.org/pdf/2501.12948)
- [Embedding Models Benchmark](https://supermemory.ai/blog/best-open-source-embedding-models-benchmarked-and-ranked/)
- [Phi-4 vs Gemma 3 Comparison](https://llm-stats.com/models/compare/gemma-3-4b-it-vs-phi-4-mini)
