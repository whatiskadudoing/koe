// KoeDomain - Core domain models and protocols for Koe (声)
//
// This package contains:
// - Models: RecordingState, TranscriptionMode, KoeModel, Language, Transcription,
//           Meeting, MeetingState, ProcessingResult, ProcessingStep, RefinementModel
// - Protocols: AudioRecordingService, TranscriptionService, TextInsertionService,
//              TranscriptionRepository, HotkeyService, TextRefinementService
// - Errors: AudioError, TranscriptionError, TextInsertionError, MeetingError, RefinementError

// Re-export all public types
@_exported import struct Foundation.UUID
@_exported import struct Foundation.Date
@_exported import struct Foundation.Data
@_exported import struct Foundation.TimeInterval
