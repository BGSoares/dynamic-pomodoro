import SwiftUI

/// Top-level router: onboarding on first run, then the phase-driven session UI.
struct MainWindowView: View {
    @ObservedObject var timer: TimerController
    @ObservedObject var settings: Settings

    var body: some View {
        Group {
            if !settings.onboardingComplete {
                OnboardingView(settings: settings, onFinish: {})
            } else {
                switch timer.phase {
                case .idle:
                    IdleView(timer: timer, settings: settings)
                case .focus:
                    FocusView(timer: timer)
                case .breakRunning:
                    // The real break UI is the full-screen overlay window;
                    // this main-window placeholder just mirrors timer state
                    // in case the user clicks back into the app window.
                    BreakMirrorView(timer: timer)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 480)
    }
}
