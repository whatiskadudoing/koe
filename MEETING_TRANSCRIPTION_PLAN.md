# Meeting Transcription Feature Plan

> **Status**: Future feature - not for immediate implementation
> **Created**: 2026-01-12

## Overview

Full-featured meeting transcription system with speaker diarization, rich metadata extraction, and LLM-powered summaries.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   AUDIO INPUT                        │
│  System Audio + Mic → AVAudioEngine                 │
└─────────────────┬───────────────────────────────────┘
                  ▼
┌─────────────────────────────────────────────────────┐
│              SPEAKER DIARIZATION                     │
│  pyannote-audio (CoreML) → Speaker segments         │
│  Output: [(start, end, speaker_id), ...]            │
└─────────────────┬───────────────────────────────────┘
                  ▼
┌─────────────────────────────────────────────────────┐
│               TRANSCRIPTION                          │
│  WhisperKit → Text + word timestamps                │
│  Per-segment or full audio with alignment           │
└─────────────────┬───────────────────────────────────┘
                  ▼
┌─────────────────────────────────────────────────────┐
│            SPEAKER IDENTIFICATION                    │
│  Voice embeddings → Match to known speakers         │
│  "Speaker 1" → "Carlos", "Speaker 2" → "Maria"     │
└─────────────────┬───────────────────────────────────┘
                  ▼
┌─────────────────────────────────────────────────────┐
│              LLM POST-PROCESSING                     │
│  Ollama/Claude → Summary, actions, decisions        │
└─────────────────┬───────────────────────────────────┘
                  ▼
┌─────────────────────────────────────────────────────┐
│                   OUTPUT                             │
│  - Full transcript with speaker labels              │
│  - Meeting summary                                   │
│  - Action items with owners                         │
│  - Searchable archive                               │
└─────────────────────────────────────────────────────┘
```

## Components

### 1. Audio Capture

| Feature | What's Needed |
|---------|---------------|
| System audio | Screen recording permission + audio tap |
| Microphone | Already have in Koe |
| Both combined | Mix system + mic for remote meetings |

### 2. Speaker Diarization (Who spoke)

| Feature | Best Tool |
|---------|-----------|
| Speaker segmentation | pyannote-audio → CoreML |
| Speaker embedding | ECAPA-TDNN or ResNet models |
| Number of speakers | Auto-detect or user-specified |
| Speaker labels | "Speaker 1" or learned names |

### 3. Transcription (What was said)

| Feature | Whisper Capability |
|---------|-------------------|
| Speech-to-text | Yes |
| Multi-language | 99+ languages |
| Translation to English | Built-in |
| Word timestamps | Yes |
| Punctuation | Yes |
| Code-switching (mixed languages) | Limited |

### 4. Rich Metadata

| Feature | How to Get |
|---------|------------|
| Timestamps | Whisper word-level timestamps |
| Confidence scores | Whisper probability output |
| Language detection | Whisper auto-detect |
| Emotion/sentiment | Separate model (e.g., emotion2vec) |
| Topic detection | LLM post-processing |
| Action items | LLM extraction |
| Summary | LLM summarization |

### 5. LLM Post-Processing

```
Raw transcript → LLM → Structured output:
- Summary
- Key decisions
- Action items (who, what, when)
- Questions raised
- Topics discussed
```

## Models Required

| Purpose | Model | Size | CoreML? |
|---------|-------|------|---------|
| Transcription | WhisperKit | 500MB-1.5GB | Already have |
| Diarization | pyannote/segmentation | ~20MB | Can convert |
| Speaker embedding | pyannote/embedding | ~20MB | Can convert |
| Summarization | Ollama (qwen/llama) | 4-8GB | Via llama.cpp |

## What Koe Already Has

- [x] Audio recording (mic)
- [x] WhisperKit transcription
- [x] Voice embeddings (VoiceVerifier)
- [x] LLM integration (Ollama)
- [x] Pipeline architecture (easy to add stages)

## What Needs to Be Added

- [ ] System audio capture (screen recording permission)
- [ ] Speaker diarization model (pyannote → CoreML conversion)
- [ ] Speaker segment alignment with transcription
- [ ] Meeting UI (longer recordings, speaker view, timeline)
- [ ] Meeting storage and search
- [ ] Export formats (markdown, PDF, etc.)

## MVP Approach

Start simple with existing components:

1. Use existing `VoiceVerifier` to detect "You" vs "Others"
2. Label transcript with 2 speakers initially
3. Add full pyannote diarization later for multi-speaker support

## References

- [pyannote-audio](https://github.com/pyannote/pyannote-audio) - Speaker diarization
- [WhisperX](https://github.com/m-bain/whisperX) - Whisper + diarization
- [ECAPA-TDNN](https://huggingface.co/speechbrain/spkrec-ecapa-voxceleb) - Speaker embeddings
