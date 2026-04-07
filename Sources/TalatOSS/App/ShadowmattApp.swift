import SwiftData
import SwiftUI

@main
struct ShadowmattApp: App {
    @StateObject private var appState = AppState()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Recording.self,
            Transcript.self,
            TranscriptSegment.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appState)
                .modelContainer(sharedModelContainer)
                .onAppear {
                    appState.setModelContext(sharedModelContainer.mainContext)
                    Task {
                        await appState.initializeApp()
                    }
                }
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Recording") {
                    appState.startNewRecording()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(appState.isRecording)
            }

            CommandGroup(after: .newItem) {
                Divider()

                Button(appState.isPaused ? "Resume Recording" : "Pause Recording") {
                    if appState.isPaused {
                        appState.resumeRecording()
                    } else {
                        appState.pauseRecording()
                    }
                }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(!appState.isRecording)

                Button("Stop Recording") {
                    Task {
                        await appState.stopRecording()
                    }
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!appState.isRecording)
            }
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
        #endif
    }
}
