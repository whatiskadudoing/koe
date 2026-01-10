# Early Test Results - Phase 1 Fast Models

**Last Updated:** 2026-01-10 11:09 AM

## Completed Tests

### 1. phi4-mini (Microsoft) ✅

**Average Speed:** 46.9 tok/s ⚡ **VERY FAST**

| Test | Duration | Speed | Quality |
|------|----------|-------|---------|
| Grammar Cleanup | 1.1s | 48.06 tok/s | ✓ Clean, removed fillers |
| Translation EN→PT | 1.1s | 47.80 tok/s | ✓ Accurate |
| Translation PT→EN | 0.8s | 48.49 tok/s | ✓ Natural |
| Tone (Casual→Formal) | 7.4s | 46.31 tok/s | ✓ Professional |
| Prompt Enhancement | 6.6s | 46.42 tok/s | ✓ Specific improvements |
| Code Dictation | 12.6s | 46.05 tok/s | ✓ Detailed function description |
| Summarization | 3.8s | 46.53 tok/s | ✓ Concise bullet points |
| Action Items | 5.3s | 46.43 tok/s | ✓ Structured with owners |
| Sentiment Analysis | 2.3s | 46.91 tok/s | ✓ Accurate mood detection |

**Strengths:**
- Consistently fast (~47 tok/s across all tests)
- Excellent for real-time dictation
- Good at structured output (math/logic focus)
- Professional tone adjustments

**Verdict:** ⭐ **Best for real-time dictation** - Instant feel, very responsive

---

### 2. mistral:7b (Baseline) ✅

**Average Speed:** 14.8 tok/s 🐢 **MEDIUM**

| Test | Duration | Speed | Quality |
|------|----------|-------|---------|
| Grammar Cleanup | 1.7s | 14.66 tok/s | ✓ Clean but kept "basically" |
| Translation EN→PT | 15.0s | 15.06 tok/s | ✓ Accurate |
| Translation PT→EN | 4.0s | 14.98 tok/s | ✓ Natural |
| Tone (Casual→Formal) | 8.2s | 21.19 tok/s | ✓ Professional |
| Prompt Enhancement | 23.3s | 17.71 tok/s | ✓ Detailed improvements |
| Code Dictation | ~15s | ~14 tok/s | ✓ Functional description |
| Summarization | ~7s | ~15 tok/s | ✓ Bullet points |
| Action Items | 6.9s | 14.66 tok/s | ✓ Structured list |
| Sentiment Analysis | 5.7s | 14.79 tok/s | ✓ Tone detected |

**Strengths:**
- Steady performance
- Good translation quality
- Decent for non-real-time tasks

**Weaknesses:**
- 3.2x slower than phi4-mini
- Noticeable delay for longer responses

**Verdict:** 🟡 **Adequate for batch processing** - Too slow for real-time dictation

---

## In Progress

### 3. qwen3:4b (Alibaba) ⏳

**Observed Speed:** 24-37 tok/s (varies by test) 🚀 **FAST**

Early observations:
- Grammar: 36.64 tok/s ✓
- Translation EN→PT: 37.74 tok/s ✓
- Translation PT→EN: 37.35 tok/s ✓
- Tone: 26.20 tok/s (slower on complex rewriting)
- Prompt Enhancement: 24.07 tok/s (testing now)

**Expected Verdict:** Fast, think-mode capable, good balance

---

### 4. qwen2.5:7b (Alibaba) ⏳

**Observed Speed:** ~16-17 tok/s 🟡 **MEDIUM-FAST**

Early observation:
- Tone test: 16.61 tok/s

**Expected Verdict:** Between mistral and qwen3, decent baseline

---

### 5. gemma3n:e2b (Google) 📥

**Status:** Downloading (93%+, ETA ~1 min)

**Expected Performance:** 30+ tok/s (edge-first model, 15% faster than Gemma 3)

---

## Speed Tiers (M1/M2/M3 Macs)

| Tier | Tokens/sec | Models | Use Case |
|------|------------|--------|----------|
| ⚡ **Very Fast** | >30 tok/s | **phi4-mini** (46.9), qwen3:4b (~30-37) | Real-time dictation |
| 🚀 **Fast** | 20-30 tok/s | gemma3n:e2b (expected) | Dictation with minimal delay |
| 🟡 **Medium** | 10-20 tok/s | mistral:7b (14.8), qwen2.5:7b (~16) | Batch processing, non-urgent |
| 🐢 **Slow** | <10 tok/s | None tested yet | Not suitable for dictation |

---

## Early Recommendations

### For Dictation Feature (Real-time)

**Winner:** **phi4-mini** 🏆
- 46.9 tok/s average (instant feel)
- Consistently fast across all test types
- Good quality on grammar, translation, tone
- Best for: Math/technical dictation, structured output

**Runner-up:** **qwen3:4b** 🥈
- ~30-37 tok/s (still very fast)
- Think mode available for complex tasks
- Good balance of speed and quality
- Best for: General dictation, flexible use

### For Meeting Feature (Summarization)

**To be tested:** qwen3:30b-a3b (MoE, 256K context)
- Expected: Best for long meetings
- Will test in Phase 3

---

## Next Steps

1. ⏳ Wait for qwen3:4b, qwen2.5:7b, gemma3n:e2b to complete
2. 📊 Generate full comparison report
3. 🧪 Test Phase 2 models (qwen3:8b, deepseek-r1:8b)
4. 🎯 Select final model for Koe dictation feature
