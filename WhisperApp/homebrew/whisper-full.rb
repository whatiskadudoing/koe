cask "whisper-full" do
  version "1.0.0"
  sha256 :no_check  # Update with actual SHA256 when releasing

  url "https://github.com/whatiskadudoing/koe/releases/download/v#{version}/Whisper-#{version}-all.dmg"
  name "Whisper (Full - All Models)"
  desc "Voice-to-text transcription app using OpenAI Whisper (all models bundled - full offline)"
  homepage "https://github.com/whatiskadudoing/koe"

  depends_on macos: ">= :ventura"

  app "Whisper.app"

  conflicts_with cask: [
    "whisper",
    "whisper-minimal",
    "whisper-base",
    "whisper-small",
    "whisper-medium",
    "whisper-large",
  ]

  zap trash: [
    "~/Library/Application Support/WhisperApp",
    "~/Library/Preferences/com.whisperapp.Whisper.plist",
  ]

  caveats <<~EOS
    WhisperApp (Full) - All models bundled for complete offline use (~5GB)

    Includes: tiny, base, small, medium, and large-v3 models

    Requires:
    1. Microphone access - grant when prompted
    2. Accessibility access - enable in System Settings > Privacy & Security > Accessibility

    Usage: Hold Option+Space to record and transcribe!
    Switch models from the menu bar icon.
  EOS
end
