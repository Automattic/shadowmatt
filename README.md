# Shadowmatt - Meeting Transcription App

A macOS-native meeting transcription app built with Swift/SwiftUI, using WhisperKit for local speech-to-text and Ollama for AI-powered summaries.

## Features

- **Live Transcription**: Real-time speech-to-text using WhisperKit (whisper.cpp)
- **Audio Capture**: Record from microphone, system audio, or both
- **AI Summaries**: Generate meeting summaries using local Ollama LLMs
- **Action Items**: Automatically extract action items from transcripts
- **Chat-Style UI**: Messages displayed as bubbles with timestamps
- **Export Options**: Export transcripts as TXT, Markdown, or JSON
- **Privacy-First**: All processing happens locally on your device

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15.0+ (for development)
- Swift 5.9+
- Ollama (for AI summaries)

## Installation

### Build from Source

```bash
# Clone the repository
git clone <your-repo-url>
cd shadowmatt

# Build and create app bundle
./build-app.sh

# Run the app
open .build/Shadowmatt.app
```

### Install Ollama (for AI Summaries)

```bash
# Install Ollama
brew install ollama

# Start Ollama service
brew services start ollama

# Pull a model
ollama pull llama3.2
```

## Usage

### Recording a Meeting

1. Click **"New Recording"** or press `Cmd+N`
2. Grant microphone permission when prompted
3. Speak - the live transcript appears in real-time
4. Click **Stop** when finished

### Viewing Summaries

1. Select a recording from the sidebar
2. Click the **"Summary"** tab
3. Click **"Generate Summary"** to create an AI summary
4. View extracted action items below the summary

### Export Options

- **TXT** - Plain text transcript
- **Markdown** - Formatted with timestamps
- **JSON** - Structured data for integrations

## Project Structure

```
shadowmatt/
├── Package.swift                 # Swift Package manifest
├── build-app.sh                  # Build script for app bundle
├── Sources/TalatOSS/
│   ├── App/
│   │   ├── ShadowmattApp.swift   # App entry point
│   │   └── AppState.swift        # Global state management
│   ├── Views/
│   │   ├── MainView.swift        # Main window with sidebar
│   │   ├── RecordingView.swift   # Live recording interface
│   │   ├── TranscriptView.swift  # Transcript viewer with summaries
│   │   └── SettingsView.swift    # Settings panel
│   ├── Models/
│   │   ├── Recording.swift       # Recording data model
│   │   ├── Transcript.swift      # Transcript data model
│   │   └── TranscriptSegment.swift
│   └── Services/
│       ├── AudioCaptureService.swift    # Microphone/system audio
│       ├── TranscriptionService.swift   # Whisper integration
│       ├── WhisperWrapper.swift         # WhisperKit wrapper
│       ├── OllamaService.swift          # Local LLM integration
│       └── ExportService.swift          # Export functionality
└── README.md
```

## Tech Stack

- **UI**: SwiftUI (macOS 14+)
- **Transcription**: WhisperKit (whisper.cpp Swift bindings)
- **Storage**: SwiftData (local SQLite)
- **AI Summaries**: Ollama (local LLMs)
- **Audio**: AVFoundation + ScreenCaptureKit

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+N` | New Recording |
| `Cmd+P` | Pause/Resume |
| `Cmd+.` | Stop Recording |

## Privacy

- All transcription happens locally using WhisperKit
- AI summaries generated locally via Ollama
- No data sent to external servers
- Recordings stored in `~/Library/Application Support/Shadowmatt/`

## Future Enhancements

- [ ] Speaker diarization
- [ ] Cloud LLM options (OpenAI, Anthropic)
- [ ] Meeting app auto-detection
- [ ] Cloud sync (iCloud/Dropbox)
- [ ] Audio playback with click-to-seek
- [ ] Webhook exports

## License

MIT License

## Contributing

Contributions welcome! Please open an issue or submit a pull request.
