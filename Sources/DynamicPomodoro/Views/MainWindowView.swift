import SwiftUI

/// Phase-driven router for the main window.
/// No onboarding screen — first launch lands on Idle with sensible defaults.
struct MainWindowView: View {
    @ObservedObject var timer: TimerEngine

    var body: some View {
        Group {
            switch timer.state.phase {
            case .idle:
                IdleView(timer: timer)
            case .focus:
                FocusView(timer: timer)
            case .breakRunning:
                // The real break UI is the full-screen overlay window;
                // this main-window placeholder just mirrors timer state
                // in case the user clicks back into the app window.
                BreakMirrorView(timer: timer)
            }
        }
        .frame(minWidth: 520, minHeight: 480)
    }
}
