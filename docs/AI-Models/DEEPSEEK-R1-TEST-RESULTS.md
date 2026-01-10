# DeepSeek R1:8b Test Results - FAILED

**Test Date:** 2026-01-10
**Test Duration:** ~15 minutes (terminated early)
**Status:** ❌ **NOT SUITABLE** for real-time dictation

---

## Executive Summary

DeepSeek R1:8b showed consistent performance on simple tasks but **catastrophic latency** on code generation, making it completely unsuitable for interactive dictation use cases.

### Test Results

| Test | Duration | Speed | Status |
|------|----------|-------|---------|
| Grammar Cleanup | 17.0s | 22.15 tok/s | ✅ Completed |
| Translation EN→PT-BR | 16.5s | 22.04 tok/s | ✅ Completed |
| Translation PT→EN | 16.4s | 22.09 tok/s | ✅ Completed |
| Tone (Casual→Formal) | 32.6s | 22.13 tok/s | ✅ Completed |
| Prompt Enhancement | 54.3s | 22.35 tok/s | ✅ Completed |
| **Code Dictation** | **15+ min** | **N/A** | ❌ **TIMEOUT** |
| Summarization | - | - | ⏸️ Not tested |
| Action Items | - | - | ⏸️ Not tested |
| Sentiment Analysis | - | - | ⏸️ Not tested |

---

## Critical Failure: Code Dictation Test

**Problem:**
The code dictation test ran for over **15 minutes** without producing output and had to be manually terminated.

**Prompt:**
```
Convert this to a clean function description: create a function called fetch user
data that takes a user ID parameter and returns a promise with the user object
from the API endpoint slash users slash user ID
```

**Expected Time:** 10-30 seconds (based on phi4-mini: 12.6s, qwen3:4b: 187s)
**Actual Time:** 15+ minutes (900+ seconds)
**Result:** Process killed - unresponsive

**Root Cause:**
DeepSeek R1's chain-of-thought reasoning model enters long thinking loops on certain prompts, causing extreme latency that is completely unacceptable for interactive use.

---

## Comparison with phi4-mini (Phase 1 Winner)

| Metric | phi4-mini | deepseek-r1:8b | Verdict |
|--------|-----------|----------------|---------|
| **Average Speed (completed tests)** | 46.9 tok/s | 22.2 tok/s | phi4-mini **2.1x faster** |
| **Grammar Cleanup** | 1.1s (48.1 tok/s) | 17.0s (22.2 tok/s) | phi4-mini **15x faster** |
| **Code Dictation** | 12.6s (46.1 tok/s) | 15+ min (TIMEOUT) | phi4-mini **70x+ faster** |
| **Consistency** | ±2 tok/s | Unpredictable (16s → 15min+) | phi4-mini **stable** |
| **Real-time Feel** | ✅ Instant | ❌ Delays, hangs | phi4-mini **usable** |

---

## Why DeepSeek R1 Failed

### Chain-of-Thought Reasoning is a Double-Edged Sword

**Advertised Benefits:**
- "Aha moments" - model can reconsider and self-correct
- 50% accuracy on AIME math problems
- Long reasoning chains with verification

**Reality for Dictation:**
- Unpredictable latency (16s on some tasks, 15+ min on others)
- Thinking loops can cause hangs
- No way to interrupt or timeout gracefully
- Reasoning overhead is unacceptable for real-time interaction

### DeepSeek R1 is Built for Accuracy, Not Speed

**Good For:**
- Math competitions (AIME)
- Complex logic puzzles
- Batch processing where time doesn't matter
- Research and deep analysis

**Bad For:**
- Real-time dictation
- Interactive applications
- User-facing features where latency matters
- Anything requiring consistent response times

---

## Final Verdict

### ❌ DeepSeek R1:8b is NOT RECOMMENDED for Koe

**Reasons:**
1. **Catastrophic latency** on code generation (15+ min timeout)
2. **2.1x slower** than phi4-mini on successful tests
3. **Unpredictable performance** - can't trust response times
4. **No real-time feel** - delays would frustrate users
5. **Better alternatives exist** - phi4-mini is faster and reliable

---

## Recommendation

**Stick with phi4-mini (Phase 1 Winner)**

| Model | Speed | Use Case | Status |
|-------|-------|----------|--------|
| **phi4-mini** | 46.9 tok/s | ✅ **Primary dictation model** | **RECOMMENDED** |
| qwen3:4b | 27.9 tok/s | ⚖️ Backup (quality-focused) | Optional |
| gemma3n:e2b | 22.4 tok/s | 📱 Edge devices | Optional |
| **deepseek-r1:8b** | **22.2 tok/s** | **❌ NOT SUITABLE** | **REJECTED** |

---

## Phase 2 Testing Status

| Model | Status | Result |
|-------|--------|--------|
| deepseek-r1:8b | ❌ Tested - Failed | Not suitable |
| phi4:14b | ⏸️ Not tested | Download available |
| qwen3:8b | ⏸️ Not tested | Download available |

**Question:** Should we continue Phase 2 testing?

**Analysis:**
- phi4-mini (2.5 GB, 46.9 tok/s) is already excellent
- Larger models (phi4:14b 9.1 GB, qwen3:8b 5.2 GB) will likely be slower
- Download size and inference cost may not justify marginal quality gains
- For dictation, **speed > quality** is the priority

**Recommendation:** Skip remaining Phase 2 tests and deploy phi4-mini.

---

**Last Updated:** 2026-01-10 11:42 AM
**Test Environment:** Mac M1+, Ollama
**Conclusion:** phi4-mini remains the clear winner for Koe dictation.
