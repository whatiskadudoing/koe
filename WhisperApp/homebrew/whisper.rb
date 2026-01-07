cask "whisper" do
  version "1.0.0"
  sha256 :no_check  # Update with actual SHA256 when releasing

  # Default: tiny model bundled (good balance of size and functionality)
  url "https://github.com/whatiskadudoing/koe/releases/download/v#{version}/Whisper-#{version}-tiny.dmg"
  name "Whisper"
  desc "Voice-to-text transcription app using OpenAI Whisper (tiny model)"
  homepage "https://github.com/whatiskadudoing/koe"

  depends_on macos: ">= :ventura"

  app "Whisper.app"

  postflight do
    # Request accessibility permissions
    system_command "/usr/bin/osascript",
                   args: ["-e", 'display notification "Grant Accessibility access in System Settings to enable auto-typing" with title "Whisper Setup"'],
                   sudo: false
  end

  zap trash: [
    "~/Library/Application Support/WhisperApp",
    "~/Library/Preferences/com.whisperapp.Whisper.plist",
  ]

  caveats <<~EOS
    WhisperApp requires:
    1. Microphone access - grant when prompted
    2. Accessibility access - enable in System Settings > Privacy & Security > Accessibility

    Usage: Hold Option+Space to record and transcribe!

    Other model variants available:
      brew install --cask whisper-base      # ~150MB - Fast
      brew install --cask whisper-small     # ~500MB - Balanced
      brew install --cask whisper-medium    # ~1.5GB - Accurate
      brew install --cask whisper-large     # ~3GB - Best accuracy
      brew install --cask whisper-full      # ~5GB - All models (offline)
      brew install --cask whisper-minimal   # ~15MB - No bundled model
  EOS
end
