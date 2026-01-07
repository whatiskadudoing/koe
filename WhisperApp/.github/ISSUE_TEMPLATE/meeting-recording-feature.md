---
name: Meeting Recording Feature
about: Track the meeting recording and speaker recognition feature
title: '[Feature] Meeting Recording with Speaker Diarization & Recognition'
labels: enhancement, feature, help wanted
assignees: ''
---

# Meeting Recording with Speaker Diarization & Recognition

## Overview

Add automatic meeting recording and transcription with intelligent speaker identification, similar to Krisp. The app should:

1. Detect when meetings are happening
2. Record both system audio (other participants) and microphone (user)
3. Transcribe using Whisper
4. Identify different speakers (diarization)
5. Remember and recognize speakers across meetings

## User Stories

- As a user, I want to automatically record my meetings without joining bots
- As a user, I want transcripts that show who said what
- As a user, I want to label speakers with names ("SPEAKER_00" → "Carolina")
- As a user, I want the app to recognize Carolina in future meetings automatically
- As a user, I want all processing to happen on-device for privacy

## Technical Approach

### Phase 1: Audio Recording
- [ ] Use **ScreenCaptureKit** (macOS 13+) to capture system audio
- [ ] Capture microphone audio simultaneously
- [ ] Combine into single audio stream
- [ ] Save recordings to `~/Documents/Whisper Meetings/`

**Key APIs:**
```swift
let config = SCStreamConfiguration()
config.capturesAudio = true           // System audio
config.captureMicrophone = true       // Mic (macOS 14+)
```

**References:**
- [Apple ScreenCaptureKit Docs](https://developer.apple.com/documentation/screencapturekit/)
- [Azayaka](https://github.com/Mnpn/Azayaka) - Simple menu bar recorder
- [SwiftCapture](https://github.com/GlennWong/SwiftCapture) - Professional recording tool

### Phase 2: Meeting Detection
- [ ] Monitor running applications for meeting apps
- [ ] Detect: Zoom, Google Meet, Microsoft Teams, Slack, Discord, WebEx
- [ ] Optional: Calendar integration for scheduled meetings
- [ ] Auto-start recording when meeting detected (with user confirmation)

**Detection approach:**
```swift
let meetingApps = ["zoom.us", "Google Meet", "Microsoft Teams", "Slack"]
NSWorkspace.shared.runningApplications.filter { app in
    meetingApps.contains { app.bundleIdentifier?.contains($0) ?? false }
}
```

### Phase 3: Speaker Diarization
- [ ] Integrate **FluidAudio** library for on-device speaker diarization
- [ ] Segment audio into speaker turns
- [ ] Label as SPEAKER_00, SPEAKER_01, etc.

**Library:** [FluidAudio](https://github.com/FluidInference/FluidAudio)
- Native Swift/CoreML
- Runs on Apple Neural Engine
- MIT/Apache 2.0 licensed

```swift
let config = OfflineDiarizerConfig()
let manager = OfflineDiarizerManager(config: config)
let result = try await manager.process(audio: samples)

for segment in result.segments {
    print("\(segment.speakerId): \(segment.startTimeSeconds)s → \(segment.endTimeSeconds)s")
}
```

### Phase 4: Speaker Recognition
- [ ] Extract voice embeddings (fingerprints) for each speaker
- [ ] Allow users to label speakers with names
- [ ] Store embeddings in local database
- [ ] Match new recordings against known speakers using cosine similarity

**How it works:**
1. Extract embedding vector for each speaker segment
2. User labels: "SPEAKER_00 = Carolina"
3. Save: `{ name: "Carolina", embedding: [0.23, -0.15, 0.87, ...] }`
4. Future meetings: compare new embeddings → find closest match

### Phase 5: UI/UX
- [ ] Meeting recording indicator in menu bar
- [ ] Meeting history view with transcripts
- [ ] Speaker management (view, rename, delete known speakers)
- [ ] Search across all meeting transcripts
- [ ] Export transcripts (TXT, Markdown, JSON)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      WhisperApp                             │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐   ┌──────────────┐   ┌────────────────┐  │
│  │ Hold-to-     │   │   Meeting    │   │   Meeting      │  │
│  │ Record Mode  │   │   Recorder   │   │   History      │  │
│  │ (existing)   │   │   (new)      │   │   (new)        │  │
│  └──────────────┘   └──────────────┘   └────────────────┘  │
│                            │                    │          │
│                            ▼                    ▼          │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                   FluidAudio                        │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌────────────┐   │   │
│  │  │   Speaker   │  │    Voice    │  │   Speaker  │   │   │
│  │  │ Diarization │  │  Embedding  │  │   Matching │   │   │
│  │  └─────────────┘  └─────────────┘  └────────────┘   │   │
│  └─────────────────────────────────────────────────────┘   │
│                            │                               │
│                            ▼                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              TranscriberService (WhisperKit)        │   │
│  └─────────────────────────────────────────────────────┘   │
│                            │                               │
│                            ▼                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                  Known Speakers DB                  │   │
│  │   Carolina: [0.23, -0.15, 0.87, ...]               │   │
│  │   João: [0.45, 0.22, -0.33, ...]                   │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## New Files to Create

```
WhisperApp/
├── MeetingRecorder.swift      # ScreenCaptureKit audio recording
├── MeetingDetector.swift      # Detect meeting apps
├── SpeakerManager.swift       # Diarization + recognition
├── KnownSpeakersDB.swift      # Store speaker embeddings
├── MeetingHistoryView.swift   # UI for meeting history
└── SpeakerManagementView.swift # UI for managing speakers
```

## Permissions Required

| Permission | Why |
|------------|-----|
| Screen Recording | Required for system audio capture (even audio-only) |
| Microphone | Capture user's voice |
| Accessibility | Auto-type transcriptions (existing) |

## Privacy Considerations

- ✅ All processing on-device (no cloud)
- ✅ Voice embeddings stored locally only
- ✅ No data leaves the device
- ✅ User must explicitly enable meeting mode
- ✅ Clear visual indicator when recording
- ✅ Easy delete for recordings and speaker data

## Research & References

### Audio Recording
- [ScreenCaptureKit Documentation](https://developer.apple.com/documentation/screencapturekit/)
- [WWDC22: Meet ScreenCaptureKit](https://developer.apple.com/videos/play/wwdc2022/10156/)
- [WWDC24: Capture HDR content](https://developer.apple.com/videos/play/wwdc2024/10088/)

### Speaker Diarization
- [FluidAudio GitHub](https://github.com/FluidInference/FluidAudio)
- [WhisperX](https://github.com/m-bain/whisperX) (Python reference)
- [Pyannote](https://huggingface.co/pyannote/speaker-diarization)

### Similar Apps (Inspiration)
- [Krisp](https://krisp.ai/) - Bot-free meeting recording
- [Otter.ai](https://otter.ai/) - Meeting transcription
- [Granola](https://granola.so/) - Meeting notes

## Open Questions

1. Should recording start automatically or require user confirmation?
2. How long should we keep recordings? (Storage management)
3. Should we support real-time transcription during meetings?
4. Cloud sync for speaker database? (optional, privacy-conscious)

## Milestones

- [ ] **v1.1** - Basic meeting recording (system + mic audio)
- [ ] **v1.2** - Meeting detection + auto-record prompt
- [ ] **v1.3** - Speaker diarization (SPEAKER_00, SPEAKER_01)
- [ ] **v1.4** - Speaker recognition (name labeling + auto-match)
- [ ] **v1.5** - Meeting history UI + search

---

**Help Wanted!** This is a significant feature. Contributions welcome for:
- ScreenCaptureKit audio capture implementation
- FluidAudio integration
- UI/UX design for meeting history
- Testing on different meeting platforms
