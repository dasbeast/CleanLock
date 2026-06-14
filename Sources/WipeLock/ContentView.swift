import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var controller: CleaningController
    @State private var warningFlash = false

    private var isWarning: Bool {
        controller.phase == .locked && controller.secondsRemaining <= 3
    }

    var body: some View {
        VStack(spacing: 22) {
            header

            statusPanel

            if controller.phase == .idle {
                durationPicker
            }

            controls

            if controller.shouldShowPermissionHint {
                permissionRow
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: controller.secondsRemaining) { _ in
            guard isWarning else {
                warningFlash = false
                return
            }
            withAnimation(.easeInOut(duration: 0.25)) {
                warningFlash.toggle()
            }
        }
        .onChange(of: controller.phase) { newPhase in
            if newPhase != .locked { warningFlash = false }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("WipeLock")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("Pause keyboard, media keys, clicks, scrolling, and trackpad gestures while you clean.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusPanel: some View {
        VStack(spacing: 8) {
            Text(controller.statusTitle)
                .font(.title3.weight(.semibold))

            Text(controller.statusDetail)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if controller.phase != .idle {
                Text(controller.displayTime)
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(isWarning ? Color.red : .primary)
                    .animation(.easeInOut(duration: 0.25), value: isWarning)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 118)
        .padding(18)
        .background(panelColor)
        .animation(.easeInOut(duration: 0.25), value: warningFlash)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var durationPicker: some View {
        Picker("Cleaning time", selection: Binding(
            get: { controller.selectedDuration },
            set: { newValue in
                DispatchQueue.main.async {
                    controller.selectedDuration = newValue
                }
            }
        )) {
            ForEach(CleaningController.cleaningDurations, id: \.self) { duration in
                Text(durationLabel(duration)).tag(duration)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Cleaning time")
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                controller.start()
            } label: {
                Text(controller.primaryButtonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!controller.canStart)

            if controller.phase == .arming {
                Button("Cancel") {
                    controller.stop()
                }
                .controlSize(.large)
            }
        }
    }

    private var permissionRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(controller.accessibilityTrusted ? Color.green : Color.orange)
                .frame(width: 9, height: 9)

            Text("macOS may ask for Accessibility or Input Monitoring permission when WipeLock starts.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)
        }
    }

    private var panelColor: Color {
        switch controller.phase {
        case .idle:
            return Color(nsColor: .controlBackgroundColor)
        case .arming:
            return Color.yellow.opacity(0.18)
        case .locked:
            if isWarning {
                return warningFlash ? Color.red.opacity(0.28) : Color.red.opacity(0.10)
            }
            return Color.teal.opacity(0.16)
        }
    }

    private func durationLabel(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m"
    }
}
