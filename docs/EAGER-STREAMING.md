# Eager Streaming Transcription

This document describes Koe's eager streaming implementation for WhisperKit transcription, which provides faster and more responsive speech-to-text conversion.

## Overview

Eager streaming processes audio chunks during recording rather than waiting until the end, resulting in:
- Faster finalization (most work done during recording)
- More responsive UI feedback
- Reduced latency for long recordings

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Recording in Progress                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Audio Buffer: [=========================================]      │
│                     ↓ (every 0.5s or on speech pause)           │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │            Eager Streaming State                         │   │
│  │  ┌─────────────────┬─────────────────────────────────┐  │   │
│  │  │ Confirmed Words │     Hypothesis Words            │  │   │
│  │  │ (stable)        │     (may change)                │  │   │
│  │  └─────────────────┴─────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Key Optimizations

### Phase 1: Audio Truncation During Streaming

Instead of re-processing the entire audio buffer on each iteration, we truncate to only process unconfirmed audio:

```swift
// Only process audio from lastAgreedSeconds onwards (with 0.5s overlap for context)
let skipSeconds = max(0, lastAgreedSeconds - 0.5)
let skipSamples = Int(skipSeconds * 16000)
let truncatedSamples = Array(samples[skipSamples...])
```

**Impact**: For a 10-second recording with 5 seconds confirmed, we only process ~5.5 seconds instead of 10 seconds - a ~45% reduction in processing time per iteration.

### Phase 2: Reduced Streaming Interval

Timer interval reduced from 1.0s to 0.5s for more responsive updates.

**Trade-off**: More CPU usage during recording, but more real-time feedback.

### Phase 3: VAD-Triggered Streaming

Instead of transcribing at fixed intervals only, we also trigger on speech pauses:

```swift
// Transcribe when:
// 1. Speech pause detected (was speaking, now silent) - captures complete phrases
// 2. OR when we have enough new audio (fallback for continuous speech)
let speechPauseDetected = wasRecentlySpeaking && !isSpeakingNow
let hasEnoughNewAudio = newAudioSeconds >= 0.4
```

**Impact**: Transcription happens at natural phrase boundaries, reducing mid-word transcriptions and improving accuracy.

## LocalAgreement Policy

Words are confirmed using the LocalAgreement-2 policy:

1. Compare words from consecutive transcription runs
2. Find longest common prefix between them
3. Words appearing in 2+ consecutive runs are "confirmed"
4. Last 2 agreed words are kept as context for next comparison

```
Run 1: "Hello world how are"
Run 2: "Hello world how are you"
        └─────────────────┘
         Common prefix (confirmed after 2 runs)
```

## Configuration

Key parameters in `EagerStreamingState`:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `tokenConfirmationsNeeded` | 2 | Runs needed to confirm a word |
| Streaming interval | 0.5s | Timer interval for streaming |
| VAD silence threshold | 0.012 | RMS threshold for speech detection |
| Audio overlap | 0.5s | Context kept when truncating |

## Performance Benchmarks

Based on [WhisperKit research](https://arxiv.org/html/2507.10860v1):

| Metric | Value |
|--------|-------|
| Hypothesis latency | ~0.45s |
| Confirmed text latency | ~1.7s |
| Real-time factor | < 1.0 (faster than real-time) |

## Supported Models

Eager streaming works with both WhisperKit models:
- **Balanced** (whisper-large-v3-turbo) - 632MB
- **Accurate** (whisper-large-v3) - 947MB

Apple Speech uses legacy streaming mode (re-transcribes full buffer).

## Files

| File | Purpose |
|------|---------|
| `EagerStreamingState.swift` | State management for confirmed vs hypothesis words |
| `WhisperKitTranscriber.swift` | `transcribeEager()` and `finalizeEagerStreaming()` methods |
| `RecordingCoordinator.swift` | Streaming timer, VAD detection, audio truncation |

## References

- [WhisperKit: On-device Real-time ASR with Billion-Scale Transformers](https://arxiv.org/html/2507.10860v1) - ICML 2025
- [WhisperKit GitHub - Speculative Decoding Issue](https://github.com/argmaxinc/WhisperKit/issues/102)
- [Whisper Streaming - LocalAgreement Policy](https://github.com/ufal/whisper_streaming)
- [CarelessWhisper - Causal Streaming Model](https://arxiv.org/html/2508.12301v1)
- [Adapting Whisper for Streaming via Two-Pass Decoding](https://arxiv.org/abs/2506.12154)

## Future Improvements

Potential optimizations not yet implemented:

1. **Speculative Decoding** - Use draft model for faster predictions
2. **Block-Diagonal Attention** - Requires model fine-tuning, 65% encoder latency reduction
3. **Configurable Confirmation Threshold** - User setting for accuracy vs speed trade-off
