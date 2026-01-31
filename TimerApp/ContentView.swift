//
//  ContentView.swift
//  TimerApp
//
//  Created by Gerson Ramirez on 28/01/26.
//

import SwiftUI
import AudioToolbox
import UIKit
import AVFoundation
import UserNotifications

enum AppColors {
    static let eggshell = Color(hex: 0xF4F1DE)
    static let burntPeach = Color(hex: 0xE07A5F)
    static let twilightIndigo = Color(hex: 0x3D405B)
    static let mutedTeal = Color(hex: 0x81B29A)

    static let appBackground = Color(hex: 0x2B2E44)
    static let raisedSurface = Color(hex: 0x454968)
    static let secondaryText = Color(hex: 0xCFCBB9)
    static let disabledText = Color(hex: 0x8F93A8)
    static let border = Color(hex: 0x58607A)
    static let primaryPressed = Color(hex: 0x6C9D87)
    static let destructivePressed = Color(hex: 0xC9664E)
    static let overlay = Color.black.opacity(0.45)
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    @State private var totalSeconds: Int = 25 * 60
    @State private var remainingSeconds: Int = 25 * 60
    @State private var isRunning = false
    @State private var isBreak = false
    @State private var showBreakPrompt = false
    @State private var completionPulse = false
    @State private var customMinutes = 25
    @State private var customSeconds = 0
    @State private var customIsBreak = false
    @State private var selectedTab: TimerTab = .presets
    @State private var audioPlayer: AVAudioPlayer?
    @State private var draggingPresetID: UUID?
    @State private var dragOffset: CGFloat = 0
    @State private var toastMessage: String?
    @State private var showToast = false
    @State private var isFullScreen = false
    @State private var startDate: Date?
    @State private var pausedRemainingSeconds: Int = 0

    @AppStorage("saved_presets") private var savedPresetsData = ""
    @State private var savedPresets: [SavedPreset] = []

    @AppStorage("default_custom_minutes") private var defaultCustomMinutes = 25
    @AppStorage("default_custom_seconds") private var defaultCustomSeconds = 0
    @AppStorage("default_custom_is_break") private var defaultCustomIsBreak = false
    @AppStorage("sound_enabled") private var soundEnabled = true
    @AppStorage("haptics_enabled") private var hapticsEnabled = true
    @AppStorage("notifications_enabled") private var notificationsEnabled = true

    private let workPresets: [TimerPreset] = [
        TimerPreset(title: "15 min", seconds: 15 * 60),
        TimerPreset(title: "25 min", seconds: 25 * 60),
        TimerPreset(title: "45 min", seconds: 45 * 60)
    ]

    private let breakPresets: [TimerPreset] = [
        TimerPreset(title: "5 min", seconds: 5 * 60),
        TimerPreset(title: "10 min", seconds: 10 * 60),
        TimerPreset(title: "15 min", seconds: 15 * 60)
    ]

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                background

                mainLayout(in: proxy.size)
                    .padding(.horizontal, horizontalSizeClass == .regular ? 40 : 20)
                    .padding(.vertical, 20)
            }
        }
        .overlay {
            if showBreakPrompt {
                breakPrompt
            }
        }
        .overlay(alignment: .top) {
            if showToast, let message = toastMessage {
                ToastView(message: message)
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onReceive(timer) { _ in
            tickTimer()
        }
        .onAppear {
            savedPresets = loadSavedPresets()
            syncCustomFromDefaults()
            updateIdleTimer()
            requestNotificationPermissionIfNeeded()
        }
        .onChange(of: savedPresetsData) { _ in
            savedPresets = loadSavedPresets()
        }
        .onChange(of: isRunning) { _ in
            updateIdleTimer()
        }
        .onChange(of: scenePhase) { phase in
            handleScenePhaseChange(phase)
        }
    }

    private func mainLayout(in size: CGSize) -> some View {
        let isRegular = horizontalSizeClass == .regular
        return Group {
            if isFullScreen {
                timerFullView
            } else if isRegular {
                HStack(spacing: 24) {
                    timerPanel
                        .frame(maxWidth: 360)

                    rightPanel
                        .frame(maxWidth: .infinity)
                }
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        timerPanel
                        rightPanel
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private var timerPanel: some View {
        VStack(spacing: 16) {
            timerCard
            actionButtonsRow
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isRunning else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                isFullScreen.toggle()
            }
        }
    }

    private var timerFullView: some View {
        VStack(spacing: 24) {
            Text(isBreak ? "Break Time" : "Focus Time")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColors.secondaryText)

            Text(timeString)
                .font(.system(size: horizontalSizeClass == .regular ? 96 : 72, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.eggshell)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isFullScreen = false
            }
        }
    }

    private var rightPanel: some View {
        VStack(spacing: 16) {
            Picker("Tabs", selection: $selectedTab) {
                ForEach(TimerTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .tint(AppColors.mutedTeal)

            rightContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private var rightContent: some View {
        switch selectedTab {
        case .presets:
            presetsPanel
        case .custom:
            customPanel
        case .config:
            configPanel
        }
    }

    private var presetsPanel: some View {
        VStack(spacing: 16) {
            panelSection(title: "Work presets") {
                presetRowInline(presets: workPresets, isBreakPreset: false)
            }

            panelSection(title: "Break presets") {
                presetRowInline(presets: breakPresets, isBreakPreset: true)
            }

            panelSection(title: "Saved presets") {
                if savedPresets.isEmpty {
                    Text("No saved presets yet.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(AppColors.secondaryText)
                } else {
                    savedPresetsList
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var customPanel: some View {
        panelSection(title: "Custom time") {
            customTimeSection
        }
    }

    private var configPanel: some View {
        VStack(spacing: 16) {
            panelSection(title: "Defaults") {
                // Added alignment: .leading and maxWidth: .infinity
                VStack(alignment: .leading, spacing: 10) {
                    Text("Default custom time")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColors.eggshell)
                    Text(defaultTimeString)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.eggshell)
                    
                    // Make buttons fill the width
                    Button("Set current custom as default") {
                        defaultCustomMinutes = customMinutes
                        defaultCustomSeconds = customSeconds
                        defaultCustomIsBreak = customIsBreak
                    }
                    .buttonStyle(ActionButtonStyle(role: .secondary))
                    .frame(maxWidth: .infinity)

                    Button("Load default into custom picker") {
                        syncCustomFromDefaults()
                    }
                    .buttonStyle(ActionButtonStyle(role: .secondary))
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            panelSection(title: "Feedback") {
                VStack(spacing: 12) { 
                    Toggle(isOn: $soundEnabled) {
                        Text("Sound on finish")
                            .foregroundStyle(AppColors.eggshell)
                    }
                    .tint(AppColors.mutedTeal)

                    Toggle(isOn: $hapticsEnabled) {
                        Text("Haptics on finish")
                            .foregroundStyle(AppColors.eggshell)
                    }
                    .tint(AppColors.mutedTeal)
                }
            }

            panelSection(title: "Data") {
                Button("Clear saved presets") {
                    savedPresets.removeAll()
                    persistPresets()
                }
                .buttonStyle(ActionButtonStyle(role: .destructive))
                .frame(maxWidth: .infinity) // Stretch button
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var timerCard: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text(isBreak ? "Break Time" : "Focus Time")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.secondaryText)
                Text(timeString)
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.eggshell)
            }

            ZStack {
                Circle()
                    .stroke(AppColors.border.opacity(0.7), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(
                            colors: isBreak ? [AppColors.mutedTeal, AppColors.primaryPressed] :
                                [AppColors.burntPeach, AppColors.destructivePressed],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.2), value: progress)

                VStack(spacing: 6) {
                    Text(isRunning ? "Running" : "Paused")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(AppColors.secondaryText)
                    Text(isBreak ? "Relax & Recharge" : "Deep Work Session")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(AppColors.secondaryText)
                }
            }
            .frame(width: 220, height: 220)
        }
        .padding(28)
        .background(cardBackground)
        .scaleEffect(completionPulse ? 1.02 : 1)
    }

    private var actionButtonsRow: some View {
        HStack(spacing: 16) {
            Button(action: toggleTimer) {
                Label(isRunning ? "Pause" : "Start", systemImage: isRunning ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ActionButtonStyle(role: .primary))

            Button(action: resetTimer) {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ActionButtonStyle(role: .destructive))
        }
    }

    private func presetRowInline(presets: [TimerPreset], isBreakPreset: Bool) -> some View {
        HStack(spacing: 12) {
            ForEach(presets) { preset in
                Button(action: {
                    setTimer(seconds: preset.seconds, breakMode: isBreakPreset)
                }) {
                    Text(preset.title)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PresetButtonStyle(isBreak: isBreakPreset))
            }
        }
    }

    private var customTimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Picker("Minutes", selection: $customMinutes) {
                    ForEach(0..<121, id: \.self) { value in
                        Text("\(value) min").tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity, maxHeight: 120)
                .clipped()

                Picker("Seconds", selection: $customSeconds) {
                    ForEach(0..<60, id: \.self) { value in
                        Text("\(value) sec").tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity, maxHeight: 120)
                .clipped()
            }

            Picker("Mode", selection: $customIsBreak) {
                Text("Work").tag(false)
                Text("Break").tag(true)
            }
            .pickerStyle(.segmented)
            .tint(AppColors.mutedTeal)

            HStack(spacing: 12) {
                Button("Start custom") {
                    startCustomTimer()
                }
                .buttonStyle(ActionButtonStyle(role: .primary))

                Button("Save preset") {
                    saveCustomPreset()
                }
                .buttonStyle(ActionButtonStyle(role: .secondary))
            }
        }
    }

    private var breakPrompt: some View {
        ZStack {
            AppColors.overlay
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Text("Great job! Time for a break?")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.eggshell)

                Text("Pick a quick break to start instantly.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(AppColors.secondaryText)

                HStack(spacing: 12) {
                    ForEach(breakPresets) { preset in
                        Button(preset.title) {
                            setTimer(seconds: preset.seconds, breakMode: true)
                            showBreakPrompt = false
                            isRunning = true
                        }
                        .buttonStyle(PresetButtonStyle(isBreak: true))
                    }
                }

                Button("Not now") {
                    showBreakPrompt = false
                }
                .buttonStyle(ActionButtonStyle(role: .secondary))
            }
            .padding(24)
            .background(cardBackground)
            .padding(.horizontal, 24)
        }
    }

    private var background: some View {
        AppColors.appBackground.ignoresSafeArea()
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(AppColors.twilightIndigo)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AppColors.border, lineWidth: 1)
            )
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(AppColors.twilightIndigo)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(AppColors.border, lineWidth: 1)
            )
    }

    private var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(remainingSeconds) / Double(totalSeconds)
    }

    private var timeString: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var defaultTimeString: String {
        let minutes = defaultCustomMinutes
        let seconds = defaultCustomSeconds
        let mode = defaultCustomIsBreak ? "Break" : "Work"
        return String(format: "%02d:%02d · %@", minutes, seconds, mode)
    }

    private func setTimer(seconds: Int, breakMode: Bool) {
        totalSeconds = seconds
        remainingSeconds = seconds
        isRunning = false
        isBreak = breakMode
        showBreakPrompt = false
        startDate = nil
        pausedRemainingSeconds = seconds
    }

    private func toggleTimer() {
        if remainingSeconds == 0 {
            resetTimer()
        }
        if isRunning {
            pausedRemainingSeconds = remainingSeconds
            startDate = nil
            cancelTimerNotification()
        } else {
            startDate = Date()
            scheduleTimerNotification()
        }
        isRunning.toggle()
    }

    private func resetTimer() {
        remainingSeconds = totalSeconds
        isRunning = false
        showBreakPrompt = false
        startDate = nil
        pausedRemainingSeconds = totalSeconds
        cancelTimerNotification()
    }

    private func startCustomTimer() {
        let seconds = max(1, customMinutes * 60 + customSeconds)
        setTimer(seconds: seconds, breakMode: customIsBreak)
        startDate = Date()
        isRunning = true
        scheduleTimerNotification()
    }

    private func saveCustomPreset() {
        let seconds = max(1, customMinutes * 60 + customSeconds)
        let title = String(format: "%02d:%02d", customMinutes, customSeconds)
        let isDuplicate = savedPresets.contains {
            $0.seconds == seconds && $0.isBreak == customIsBreak
        }

        if isDuplicate {
            showUserFeedback(message: "Preset already exists")
            return
        }

        let newPreset = SavedPreset(title: title, seconds: seconds, isBreak: customIsBreak)
        savedPresets.append(newPreset)
        persistPresets()
        showUserFeedback(message: "Preset saved")
    }

    private func moveSavedPresets(from source: IndexSet, to destination: Int) {
        savedPresets.move(fromOffsets: source, toOffset: destination)
        persistPresets()
    }

    private func deleteSavedPresets(at offsets: IndexSet) {
        savedPresets.remove(atOffsets: offsets)
        persistPresets()
    }

    private func persistPresets() {
        guard let data = try? JSONEncoder().encode(savedPresets),
              let string = String(data: data, encoding: .utf8) else {
            return
        }
        savedPresetsData = string
    }

    private func loadSavedPresets() -> [SavedPreset] {
        guard let data = savedPresetsData.data(using: .utf8),
              let presets = try? JSONDecoder().decode([SavedPreset].self, from: data) else {
            return []
        }
        return presets
    }

    private func syncCustomFromDefaults() {
        customMinutes = defaultCustomMinutes
        customSeconds = defaultCustomSeconds
        customIsBreak = defaultCustomIsBreak
    }
    
    private func playAlarmSound() {
        let systemSoundPath = "/System/Library/Audio/UISounds/alarm.caf"
        let url = URL(fileURLWithPath: systemSoundPath)

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)

            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            print("Error playing system sound: \(error.localizedDescription)")
            
            AudioServicesPlayAlertSound(SystemSoundID(1005))
        }
    }

    private func handleTimerFinished() {
        cancelTimerNotification()
        if soundEnabled {
            playAlarmSound()
        }
        
        if hapticsEnabled {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
        }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            completionPulse = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeOut(duration: 0.2)) {
                completionPulse = false
            }
        }
    }

    private func tickTimer() {
        guard isRunning else { return }
        updateRemainingFromStartDate()
    }

    private func panelSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColors.secondaryText)
            
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelBackground)
    }

    private var savedPresetsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(savedPresets) { preset in
                    let isDragging = draggingPresetID == preset.id
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preset.title)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppColors.eggshell)
                            Text(preset.isBreak ? "Break" : "Work")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AppColors.secondaryText)
                        }

                        Spacer()

                        HStack(spacing: 16) {
                            Button(action: {
                                setTimer(seconds: preset.seconds, breakMode: preset.isBreak)
                            }) {
                                Image(systemName: "play.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(AppColors.mutedTeal)

                            Button(role: .destructive) {
                                if let index = savedPresets.firstIndex(where: { $0.id == preset.id }) {
                                    deletePreset(at: index)
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(AppColors.burntPeach)

                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(AppColors.secondaryText)
                                .padding(.leading, 4)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 6)
                                        .onChanged { value in
                                            handleReorderDragChange(for: preset, translation: value.translation.height)
                                        }
                                        .onEnded { _ in
                                            handleReorderDragEnd()
                                        }
                                )
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppColors.raisedSurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppColors.border.opacity(0.6), lineWidth: 1)
                    )
                    .offset(y: isDragging ? dragOffset : 0)
                    .zIndex(isDragging ? 1 : 0)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 300)
    }
    
    private func deletePreset(at index: Int) {
        guard savedPresets.indices.contains(index) else { return }
        savedPresets.remove(at: index)
        persistPresets()
    }

    private func handleReorderDragChange(for preset: SavedPreset, translation: CGFloat) {
        let rowHeight: CGFloat = 80

        if draggingPresetID == nil {
            draggingPresetID = preset.id
            dragOffset = 0
        }

        guard draggingPresetID == preset.id,
              let currentIndex = savedPresets.firstIndex(where: { $0.id == preset.id }) else {
            return
        }

        dragOffset = translation

        if translation > rowHeight * 0.6, currentIndex < savedPresets.count - 1 {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                savedPresets.swapAt(currentIndex, currentIndex + 1)
            }
            dragOffset -= rowHeight
        } else if translation < -rowHeight * 0.6, currentIndex > 0 {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                savedPresets.swapAt(currentIndex, currentIndex - 1)
            }
            dragOffset += rowHeight
        }
    }

    private func handleReorderDragEnd() {
        draggingPresetID = nil
        dragOffset = 0
        persistPresets()
    }

    private func showUserFeedback(message: String) {
        toastMessage = message
        withAnimation(.easeOut(duration: 0.2)) {
            showToast = true
        }

        if hapticsEnabled {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeIn(duration: 0.2)) {
                showToast = false
            }
        }
    }

    private func updateRemainingFromStartDate() {
        guard let startDate else { return }
        let elapsed = Int(Date().timeIntervalSince(startDate))
        let newRemaining = max(0, pausedRemainingSeconds - elapsed)
        if newRemaining != remainingSeconds {
            remainingSeconds = newRemaining
        }
        if remainingSeconds == 0 {
            isRunning = false
            showBreakPrompt = true
            handleTimerFinished()
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            if isRunning {
                updateRemainingFromStartDate()
            }
        case .background, .inactive:
            if isRunning {
                updateRemainingFromStartDate()
            }
        @unknown default:
            break
        }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = isRunning
    }

    private func requestNotificationPermissionIfNeeded() {
        guard notificationsEnabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func scheduleTimerNotification() {
        guard notificationsEnabled, remainingSeconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = isBreak ? "Break finished" : "Focus finished"
        content.body = isBreak ? "Ready to get back to work." : "Time for a break."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(remainingSeconds), repeats: false)
        let request = UNNotificationRequest(identifier: "timerFinished", content: content, trigger: trigger)

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["timerFinished"])
        center.add(request)
    }

    private func cancelTimerNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["timerFinished"])
    }
}

enum TimerTab: String, CaseIterable, Identifiable {
    case presets
    case custom
    case config

    var id: String { rawValue }

    var title: String {
        switch self {
        case .presets: return "Presets"
        case .custom: return "My time"
        case .config: return "Setting"
        }
    }
}

struct TimerPreset: Identifiable {
    let id = UUID()
    let title: String
    let seconds: Int
}

struct SavedPreset: Identifiable, Codable {
    let id: UUID
    let title: String
    let seconds: Int
    let isBreak: Bool

    init(title: String, seconds: Int, isBreak: Bool) {
        self.id = UUID()
        self.title = title
        self.seconds = seconds
        self.isBreak = isBreak
    }
}

enum ActionButtonRole {
    case primary
    case secondary
    case destructive
}
struct PresetButtonStyle: ButtonStyle {
    let isBreak: Bool

    func makeBody(configuration: Configuration) -> some View {
        let accent = isBreak ? AppColors.burntPeach : AppColors.mutedTeal
        let pressedBackground = AppColors.raisedSurface
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(configuration.isPressed ? pressedBackground : AppColors.twilightIndigo)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(accent, lineWidth: 1)
            )
            .foregroundStyle(AppColors.eggshell)
    }
}

struct ActionButtonStyle: ButtonStyle {
    let role: ActionButtonRole

    func makeBody(configuration: Configuration) -> some View {
        let background: Color = {
            switch role {
            case .primary:
                return configuration.isPressed ? AppColors.primaryPressed : AppColors.mutedTeal
            case .destructive:
                return configuration.isPressed ? AppColors.destructivePressed : AppColors.burntPeach
            case .secondary:
                return configuration.isPressed ? AppColors.raisedSurface : AppColors.twilightIndigo
            }
        }()

        let foreground: Color = {
            switch role {
            case .secondary:
                return AppColors.eggshell
            case .primary, .destructive:
                return AppColors.appBackground
            }
        }()

        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(role == .secondary ? AppColors.border : .clear, lineWidth: 1)
            )
            .foregroundStyle(foreground)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(AppColors.eggshell)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppColors.twilightIndigo)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
            )
            .shadow(color: AppColors.appBackground.opacity(0.4), radius: 10, x: 0, y: 6)
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
