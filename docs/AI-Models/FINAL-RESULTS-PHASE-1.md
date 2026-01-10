# Phase 1 Model Testing - Final Results

**Test Date:** 2026-01-10
**Models Tested:** 5
**Test Categories:** 9 per model
**Total Tests Run:** 45

---

## Executive Summary

### 🏆 Winner: phi4-mini (Microsoft)

**Average Speed:** 46.9 tok/s
**Best Use Case:** Real-time dictation, technical/math content, structured output
**Verdict:** ⭐⭐⭐⭐⭐ **Best for instant, real-time dictation**

### Performance Rankings

| Rank | Model | Avg Speed | Performance Tier | Best For |
|------|-------|-----------|------------------|----------|
| 🥇 **1st** | **phi4-mini** | **46.9 tok/s** | ⚡ Very Fast | Real-time dictation |
| 🥈 **2nd** | **qwen3:4b** | **27.9 tok/s** | 🚀 Fast | Balanced speed/quality, think mode |
| 🥉 **3rd** | **gemma3n:e2b** | **22.4 tok/s** | 🚀 Fast | Edge devices, multimodal |
| 4th | qwen2.5:7b | 16.2 tok/s | 🟡 Medium-Fast | Batch processing |
| 5th | mistral:7b | 14.8 tok/s | 🟡 Medium | Translation baseline |

---

## Detailed Results

### 1. phi4-mini (Microsoft) - 🥇 WINNER

**Size:** 2.5 GB
**Average Speed:** 46.9 tok/s
**Speed Range:** 46.05 - 48.49 tok/s (very consistent)

#### Performance by Test

| Test | Duration | Speed | Quality |
|------|----------|-------|---------|
| Grammar Cleanup | 1.1s | 48.06 tok/s | ✅ Excellent - removed all fillers |
| Translation EN→PT | 1.1s | 47.80 tok/s | ✅ Accurate, natural |
| Translation PT→EN | 0.8s | **48.49 tok/s** 🔥 Fastest | ✅ Fluent |
| Tone (Casual→Formal) | 7.4s | 46.31 tok/s | ✅ Professional |
| Prompt Enhancement | 6.6s | 46.42 tok/s | ✅ Specific, actionable |
| Code Dictation | 12.6s | 46.05 tok/s | ✅ Detailed, technical |
| Summarization | 3.8s | 46.53 tok/s | ✅ Concise bullet points |
| Action Items | 5.3s | 46.43 tok/s | ✅ Structured with owners |
| Sentiment Analysis | 2.3s | 46.91 tok/s | ✅ Accurate tone detection |

**Strengths:**
- ⚡ Consistently fastest across ALL tests
- 📊 Excellent for math/logic/structured data (Microsoft's focus)
- 🎯 Very stable performance (±2 tok/s variance)
- ⏱️ Real-time feel - instant responses

**Weaknesses:**
- None significant for dictation use case

**Recommendation:** ⭐⭐⭐⭐⭐ **PRIMARY CHOICE for Koe dictation**

---

### 2. qwen3:4b (Alibaba) - 🥈 Runner-up

**Size:** 2.5 GB
**Average Speed:** 27.9 tok/s
**Speed Range:** 24.07 - 37.74 tok/s (more variable)

#### Performance by Test

| Test | Duration | Speed | Quality |
|------|----------|-------|---------|
| Grammar Cleanup | 141.9s | 36.64 tok/s | ✅ Clean, professional |
| Translation EN→PT | 68.1s | **37.74 tok/s** 🔥 Fastest | ✅ Accurate |
| Translation PT→EN | 84.7s | 37.35 tok/s | ✅ Natural |
| Tone (Casual→Formal) | 37.9s | 26.20 tok/s | ✅ Very detailed rewrite |
| Prompt Enhancement | 82.0s | 24.07 tok/s | ✅ Technical, precise |
| Code Dictation | 187.5s | 26.52 tok/s | ✅ Production-ready code |
| Summarization | 22.5s | 27.35 tok/s | ✅ Bullet points with context |
| Action Items | 20.2s | 33.58 tok/s | ✅ Table format |
| Sentiment Analysis | 68.4s | 27.86 tok/s | ✅ Detailed analysis |

**Strengths:**
- 🧠 Think mode available for complex reasoning
- 📝 Very detailed, thorough responses
- 🌐 Multilingual capabilities
- ⚖️ Good balance of speed and quality

**Weaknesses:**
- 🔄 More variable speed (24-37 tok/s)
- ⏱️ Slower on complex tasks (prompt enhancement: 82s)

**Recommendation:** ⭐⭐⭐⭐ **ALTERNATE CHOICE** - Good for quality-focused dictation

---

### 3. gemma3n:e2b (Google) - 🥉 Third Place

**Size:** 5.6 GB (but optimized for edge)
**Average Speed:** 22.4 tok/s
**Speed Range:** 21.84 - 24.17 tok/s (very consistent)

#### Performance Summary

| Test Category | Average Speed | Quality |
|---------------|---------------|---------|
| Grammar | 22.66 tok/s | ✅ Good cleanup |
| Translation | ~22 tok/s | ✅ Accurate |
| Tone | ~22 tok/s | ✅ Professional |
| Meetings | 22.31-22.40 tok/s | ✅ Concise summaries |

**Strengths:**
- 🎯 Very consistent speed (~22 tok/s)
- 📱 Edge-first design (optimized for on-device)
- 🌐 Multimodal (text, image, video, audio)
- 🌍 Multilingual (140 languages text, 35 multimodal)
- 📊 15% faster than Gemma 3 (Aug 2025 update)

**Weaknesses:**
- 📦 Larger download (5.6 GB vs 2.5 GB)
- 🐢 2.1x slower than phi4-mini

**Recommendation:** ⭐⭐⭐ **GOOD** - Best for offline/edge use cases

---

### 4. qwen2.5:7b (Alibaba) - Baseline

**Size:** 4.7 GB
**Average Speed:** 16.2 tok/s
**Speed Range:** 15.86 - 16.61 tok/s

**Strengths:**
- ⚖️ Stable, predictable
- 🌐 Good multilingual support

**Weaknesses:**
- 🐢 2.9x slower than phi4-mini
- 📦 Larger size

**Recommendation:** ⭐⭐ **SKIP** - Outperformed by qwen3:4b and phi4-mini

---

### 5. mistral:7b - Baseline

**Size:** 4.4 GB
**Average Speed:** 14.8 tok/s
**Speed Range:** 14.66 - 21.19 tok/s

**Strengths:**
- 🌐 Translation quality
- 📝 Detailed responses on complex prompts

**Weaknesses:**
- 🐢 3.2x slower than phi4-mini
- ⏱️ Noticeable delay

**Recommendation:** ⭐⭐ **SKIP** - Outperformed by all newer models

---

## Speed Comparison Chart

```
Speed (tokens/second)
│
50│  ████████████
  │  ████████████  phi4-mini (46.9 tok/s)
40│  ████████████
  │
30│      ██████    qwen3:4b (27.9 tok/s)
  │
20│        ████    gemma3n:e2b (22.4 tok/s)
  │          ███   qwen2.5:7b (16.2 tok/s)
10│          ███   mistral:7b (14.8 tok/s)
  │
0 └─────────────────────────────────────
   phi4  qwen3  gemma  qwen2.5  mistral
```

---

## Key Insights

### 1. Microsoft phi4-mini is the Clear Winner
- **46.9 tok/s** - Nearly 2x faster than the next competitor
- Instant, real-time dictation experience
- Excellent for Koe's use case

### 2. Size vs Speed Trade-off
- **Smaller is faster:** 2.5 GB models (phi4-mini, qwen3:4b) outperform 4-5 GB models
- Exception: gemma3n:e2b (5.6 GB) optimized for edge, still decent at 22.4 tok/s

### 3. Consistency Matters
- **phi4-mini:** ±2 tok/s variance (very stable)
- **qwen3:4b:** ±13 tok/s variance (task-dependent)
- **gemma3n:e2b:** ±2 tok/s variance (very stable)

### 4. Quality is Comparable
All models produce good quality output for:
- Grammar cleanup
- Translation (EN↔PT-BR)
- Tone adjustment
- Meeting summarization

The main differentiator is **speed**, not quality.

---

## Final Recommendation for Koe

### Primary Model: **phi4-mini** 🏆

**Reasons:**
1. ⚡ **46.9 tok/s** - Real-time dictation feel
2. 📦 **Small size** (2.5 GB) - Fast download, low disk usage
3. 🎯 **Consistent** - Stable performance across all tests
4. ✅ **Quality** - Excellent grammar, translation, tone
5. 💻 **Math/Tech focus** - Perfect for code dictation

**Integration:**
```swift
// Update KoeApp/Koe/JobScheduler/JobScheduler.swift
enum AIModel: String, CaseIterable {
    case fast = "phi4-mini"           // PRIMARY - Real-time dictation
    case balanced = "qwen3:4b"        // Backup - Quality-focused
    case translate = "mistral:7b"     // Keep for translation baseline
}
```

### Backup Model: **qwen3:4b** 🥈

Use when:
- User wants more detailed responses
- Complex reasoning needed (think mode)
- Translation quality is critical

### Edge Use Case: **gemma3n:e2b** 🥉

Use when:
- Offline/on-device is critical
- Multimodal input needed
- Consistent 22 tok/s is acceptable

---

## Next Steps

### Immediate Actions
1. ✅ Update Koe to use phi4-mini as default "Fast AI" model
2. ✅ Test phi4-mini integration in actual Koe dictation workflow
3. ✅ Measure real-world latency (model load + inference)

### Optional Phase 2 Testing
If phi4-mini doesn't meet quality needs, test:
- **phi4:14b** - Larger version, better quality, slower
- **qwen3:8b** - Larger Qwen with think mode
- **deepseek-r1:8b** - Reasoning specialist

### Future Enhancements
- **Meeting Feature:** Test qwen3:30b-a3b (MoE, 256K context)
- **Embeddings:** Test nomic-embed-text, Qwen3-Embedding for search
- **Reranking:** Test Qwen3-Reranker for better search results

---

## Resources

- Test scripts: `docs/AI-Models/test-model.sh`
- Raw reports: `docs/AI-Models/reports/`
- Test plan: `docs/AI-Models/AI-Model-Test-Plan.md`
- Early results: `docs/AI-Models/EARLY-RESULTS.md`

---

**Generated:** 2026-01-10 11:15 AM
**Total Testing Time:** ~30 minutes
**Models Downloaded:** 13.1 GB (5 models)
