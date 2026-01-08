// KoeDomain - Core domain models and protocols for Koe (声)
//
// This package contains:
// - Models: RecordingState, TranscriptionMode, KoeModel, Language, Transcription,
//           Meeting, MeetingState
// - Protocols: AudioRecordingService, TranscriptionService, TextInsertionService,
//              TranscriptionRepository, HotkeyService
// - Errors: AudioError, TranscriptionError, TextInsertionError, MeetingError

// Re-export all public types
@_exported import struct Foundation.UUID
@_exported import struct Foundation.Date
@_exported import struct Foundation.Data
@_exported import struct Foundation.TimeInterval
