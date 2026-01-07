cask "whisper-large" do
  version "1.0.0"
  sha256 :no_check  # Update with actual SHA256 when releasing

  url "https://github.com/whatiskadudoing/koe/releases/download/v#{version}/Whisper-#{version}-large-v3.dmg"
  name "Whisper (Large Model)"
  desc "Voice-to-text transcription app using OpenAI Whisper (large-v3 model - best accuracy)"
  homepage "https://github.com/whatiskadudoing/koe"

  depends_on macos: ">= :ventura"

  app "Whisper.app"

  conflicts_with cask: [
    "whisper",
    "whisper-minimal",
    "whisper-base",
    "whisper-small",
    "whisper-medium",
    "whisper-full",
  ]

  zap trash: [
    "~/Library/Application Support/WhisperApp",
    "~/Library/Preferences/com.whisperapp.Whisper.plist",
  ]

  caveats <<~EOS
    WhisperApp (Large Model) - Best accuracy, ~3GB download

    Requires:
    1. Microphone access - grant when prompted
    2. Accessibility access - enable in System Settings > Privacy & Security > Accessibility

    Usage: Hold Option+Space to record and transcribe!
  EOS
end
