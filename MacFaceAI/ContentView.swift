import SwiftUI

private enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case faces
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .faces: "Face profiles"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "viewfinder"
        case .faces: "person.crop.rectangle.stack"
        case .settings: "gearshape"
        }
    }
}

private enum CaptureFlow: Equatable {
    case idle
    case enrolling
    case recognizing
}

struct ContentView: View {
    @State private var camera = CameraService()
    @State private var settingsStore = SettingsStore()
    @State private var library = FaceLibrary(keychain: KeychainStore(service: "com.macfaceai.MacFaceAI"))
    @State private var passwordService = PasswordService(keychain: KeychainStore(service: "com.macfaceai.MacFaceAI"))
    @State private var section: AppSection? = .overview
    @State private var flow = CaptureFlow.idle
    @State private var isCameraActive = false
    @State private var profileName = ""
    @State private var enrollmentSamples: [EnrollmentSample] = []
    @State private var lastEnrollmentSampleTime: TimeInterval = -.greatestFiniteMagnitude
    @State private var livenessDetector = LivenessDetector()
    @State private var livenessPhase: LivenessPhase = .waitingForFace
    @State private var latestProbe: ProbeEmbedding?
    @State private var matchDecision: MatchDecision?
    @State private var statusMessage = ""
    @State private var touchIDMessage = ""
    @State private var isTouchIDRunning = false
    @State private var pendingDelete: FaceProfile?
    @State private var biometricService = BiometricAuthService()
    @State private var hasAppPassword = false
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var passwordConfirmation = ""
    @State private var passwordMessage = ""

    private let enrollmentSampleLimit = 6

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                ForEach(AppSection.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(Optional(item))
                }
            }
            .navigationTitle("MacFace AI")
            .listStyle(.sidebar)
            .frame(minWidth: 190)
        } detail: {
            Group {
                switch section ?? .overview {
                case .overview:
                    overview
                case .faces:
                    profiles
                case .settings:
                    settings
                }
            }
            .frame(minWidth: 620, minHeight: 520)
        }
        .preferredColorScheme(preferredColorScheme)
        .onChange(of: camera.frameID) { _, _ in
            processLatestSnapshot()
        }
        .confirmationDialog(
            "Delete \(pendingDelete?.displayName ?? "this profile")?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Face Profile", role: .destructive) {
                deletePendingProfile()
            }
        } message: {
            Text("The encrypted face template will be removed from this Mac.")
        }
        .onDisappear {
            stopCapture()
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                pageHeader(
                    title: "Face recognition",
                    subtitle: "Private, on-device face matching for this app."
                )

                HStack(spacing: 16) {
                    metricCard(title: "Enrolled faces", value: "\(library.profiles.count)", symbol: "person.2")
                    metricCard(title: "Camera", value: camera.status == .running ? "Active" : "Standby", symbol: "camera")
                    metricCard(title: "Successful checks", value: "\(settingsStore.settings.successfulAuthentications)", symbol: "checkmark.shield")
                }

                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Live camera")
                                .font(.headline)
                            Spacer()
                            Circle()
                                .fill(camera.status == .running ? .green : .secondary.opacity(0.45))
                                .frame(width: 8, height: 8)
                            Text(camera.dashboardStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        CameraPreview(session: camera.session)
                            .frame(minHeight: 290)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                            }
                            .overlay(alignment: .top) {
                                scannerNotch
                                    .padding(.top, 12)
                            }
                            .overlay(alignment: .bottomLeading) {
                                if let snapshot = camera.snapshot, snapshot.facesCount == 1 {
                                    Label("Face detected", systemImage: "viewfinder")
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(.regularMaterial, in: Capsule())
                                        .padding(12)
                                }
                            }

                        if let snapshot = camera.snapshot, let note = snapshot.statusNote {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Button(isCameraActive ? "Stop camera" : "Start camera") {
                            isCameraActive ? stopCapture() : startPreview()
                        }
                        .buttonStyle(.bordered)
                        .disabled(flow != .idle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 16) {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Recognize a face", systemImage: "faceid")
                                    .font(.headline)
                                Text("Run an on-device comparison against your enrolled profiles.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if settingsStore.settings.requireLiveness {
                                    livenessProgress
                                }
                                Button(flow == .recognizing ? "Stop recognition" : "Start recognition") {
                                    flow == .recognizing ? stopCapture() : beginRecognition()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(library.profiles.isEmpty && flow != .recognizing)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let decision = matchDecision {
                            matchResult(decision)
                        }

                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Touch ID", systemImage: "touchid")
                                    .font(.headline)
                                Text(biometricService.availability().detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button(isTouchIDRunning ? "Waiting for Touch ID…" : "Verify with Touch ID") {
                                    verifyWithTouchID()
                                }
                                .disabled(isTouchIDRunning || !settingsStore.settings.allowTouchID || !biometricService.availability().isAvailable)
                                if !touchIDMessage.isEmpty {
                                    Text(touchIDMessage)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(width: 270)
                }

                if !statusMessage.isEmpty {
                    Label(statusMessage, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("This prototype only verifies identity inside MacFace AI. It cannot unlock the macOS login window. Camera-based liveness checks reduce some replay risks but cannot guarantee protection against sophisticated spoofing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(28)
        }
    }

    private var profiles: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                pageHeader(
                    title: "Face profiles",
                    subtitle: "Enroll multiple people. Templates are encrypted and stored locally."
                )

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Register a face")
                            .font(.headline)
                        Text("Enter a name, then keep one face in frame while six samples are captured.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField("Profile name", text: $profileName)
                                .textFieldStyle(.roundedBorder)
                                .disabled(flow == .enrolling)
                            Button(flow == .enrolling ? "Cancel" : "Start registration") {
                                flow == .enrolling ? stopCapture() : beginEnrollment()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && flow != .enrolling)
                        }
                        if flow == .enrolling {
                            ProgressView(value: Double(enrollmentSamples.count), total: Double(enrollmentSampleLimit))
                            Text("Captured \(enrollmentSamples.count) of \(enrollmentSampleLimit) samples")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            CameraPreview(session: camera.session)
                                .frame(height: 250)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(alignment: .top) {
                                    scannerNotch
                                        .padding(.top, 12)
                                }
                        }
                        if !statusMessage.isEmpty {
                            Text(statusMessage)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let error = library.loadError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }

                VStack(spacing: 10) {
                    if library.profiles.isEmpty {
                        ContentUnavailableView(
                            "No enrolled faces",
                            systemImage: "person.crop.rectangle",
                            description: Text("Register a face to enable local recognition.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        ForEach(library.profiles) { profile in
                            HStack(spacing: 14) {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(profile.displayName)
                                        .font(.headline)
                                    Text("\(profile.samples.count) samples · Updated \(profile.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    pendingDelete = profile
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .labelStyle(.iconOnly)
                                .help("Delete \(profile.displayName)")
                            }
                            .padding(14)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
            }
            .padding(28)
        }
    }

    private var settings: some View {
        Form {
            pageHeader(title: "Settings", subtitle: "Tune local matching and app appearance.")

            Section("Recognition") {
                Toggle("Require blink and head-turn liveness check", isOn: $settingsStore.settings.requireLiveness)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Similarity threshold")
                        Spacer()
                        Text(settingsStore.settings.similarityThreshold, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }
                    Slider(value: $settingsStore.settings.similarityThreshold, in: 0.50...0.98, step: 0.01)
                    Text("A higher threshold is stricter. Vision feature-print scores are not calibrated for secure account authentication.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Authentication") {
                Toggle("Allow Touch ID verification in this app", isOn: $settingsStore.settings.allowTouchID)
                LabeledContent("Biometrics", value: biometricService.availability().detail)
                Text("Touch ID authorizes actions inside this app only; macOS controls system login authentication.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("App password") {
                if hasAppPassword {
                    SecureField("Current password", text: $currentPassword)
                }
                SecureField(hasAppPassword ? "New password" : "Password", text: $newPassword)
                SecureField("Confirm password", text: $passwordConfirmation)
                HStack {
                    Button(hasAppPassword ? "Change password" : "Set password") {
                        saveAppPassword()
                    }
                    .disabled(newPassword.isEmpty || passwordConfirmation.isEmpty || (hasAppPassword && currentPassword.isEmpty))
                    if hasAppPassword {
                        Button("Remove password", role: .destructive) {
                            removeAppPassword()
                        }
                        .disabled(currentPassword.isEmpty)
                    }
                }
                if !passwordMessage.isEmpty {
                    Text(passwordMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Only a salted PBKDF2 hash is stored in Keychain. The password is not saved as plain text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Picker("Color scheme", selection: $settingsStore.settings.appearance) {
                    ForEach(AppAppearance.allCases, id: \.self) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Privacy") {
                Label("Face analysis and template matching run locally.", systemImage: "iphone.and.lock")
                Label("Encrypted templates are kept in the app's Application Support folder; the encryption key is in Keychain.", systemImage: "lock.doc")
                Text("The recognizer uses Apple's Vision image feature prints. This project does not include an ArcFace Core ML model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .frame(maxWidth: 780)
        .onAppear {
            refreshPasswordStatus()
        }
    }

    private var livenessProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "livephoto")
                Text(livenessPhase.title)
                    .font(.caption.weight(.semibold))
            }
            Text(livenessPhase.instruction)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private var scannerNotch: some View {
        HStack(spacing: 8) {
            Image(systemName: flow == .enrolling ? "person.crop.circle.badge.plus" : "waveform.path.ecg")
                .symbolEffect(.pulse, options: .repeating, isActive: flow != .idle)
            Text(flow == .enrolling ? "Registering face" : "Face scanner")
                .font(.caption.weight(.semibold))
            if flow != .idle {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .foregroundStyle(.white)
        .background(.black.opacity(0.82), in: Capsule())
        .animation(.easeInOut(duration: 0.2), value: flow)
    }

    private func pageHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricCard(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.headline)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func matchResult(_ decision: MatchDecision) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    decision.accepted ? "Match found" : "No match",
                    systemImage: decision.accepted ? "checkmark.shield.fill" : "xmark.shield"
                )
                .font(.headline)
                .foregroundStyle(decision.accepted ? .green : .primary)
                if let name = decision.displayName {
                    Text(name)
                        .font(.title3.weight(.semibold))
                }
                Text("Similarity \(decision.similarity, format: .percent.precision(.fractionLength(1)))")
                    .font(.caption.monospacedDigit())
                Text(decision.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch settingsStore.settings.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private func startPreview() {
        guard !isCameraActive else { return }
        camera.acquire()
        isCameraActive = true
    }

    private func stopCapture() {
        flow = .idle
        enrollmentSamples.removeAll()
        latestProbe = nil
        isCameraActive = false
        camera.release()
    }

    private func beginEnrollment() {
        let name = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        stopCaptureIfNeeded()
        enrollmentSamples = []
        lastEnrollmentSampleTime = -.greatestFiniteMagnitude
        matchDecision = nil
        statusMessage = "Center your face and hold still while samples are collected."
        flow = .enrolling
        startPreview()
    }

    private func beginRecognition() {
        guard !library.profiles.isEmpty else {
            statusMessage = "Enroll a face profile before starting recognition."
            return
        }
        stopCaptureIfNeeded()
        matchDecision = nil
        latestProbe = nil
        livenessDetector.reset()
        livenessPhase = .waitingForFace
        statusMessage = settingsStore.settings.requireLiveness
            ? "Follow the blink and head-turn instructions."
            : "Keep one face in frame for local matching."
        flow = .recognizing
        startPreview()
    }

    private func stopCaptureIfNeeded() {
        if isCameraActive {
            camera.release()
            isCameraActive = false
        }
    }

    private func processLatestSnapshot() {
        guard let snapshot = camera.snapshot else { return }

        switch flow {
        case .idle:
            break
        case .enrolling:
            captureEnrollmentSample(from: snapshot)
        case .recognizing:
            processRecognitionFrame(snapshot)
        }
    }

    private func captureEnrollmentSample(from snapshot: FaceSnapshot) {
        guard snapshot.facesCount == 1,
              let featurePrint = snapshot.featurePrint,
              let geometry = snapshot.geometry,
              snapshot.time - lastEnrollmentSampleTime >= 0.45 else {
            return
        }
        lastEnrollmentSampleTime = snapshot.time
        enrollmentSamples.append(
            EnrollmentSample(
                featurePrint: featurePrint,
                geometry: geometry,
                quality: snapshot.quality ?? 0,
                capturedAt: Date()
            )
        )
        guard enrollmentSamples.count >= enrollmentSampleLimit else { return }

        do {
            try library.upsert(displayName: profileName, samples: Array(enrollmentSamples.prefix(enrollmentSampleLimit)))
            statusMessage = "\(profileName.trimmingCharacters(in: .whitespacesAndNewlines)) was enrolled on this Mac."
            profileName = ""
            flow = .idle
            stopCaptureIfNeeded()
        } catch {
            statusMessage = error.localizedDescription
            flow = .idle
            stopCaptureIfNeeded()
        }
    }

    private func processRecognitionFrame(_ snapshot: FaceSnapshot) {
        if snapshot.facesCount == 1,
           let featurePrint = snapshot.featurePrint,
           let geometry = snapshot.geometry {
            latestProbe = ProbeEmbedding(featurePrint: featurePrint, geometry: geometry)
        }

        if settingsStore.settings.requireLiveness {
            livenessPhase = livenessDetector.ingest(
                PoseSample(
                    time: snapshot.time,
                    facePresent: snapshot.facesCount == 1,
                    yaw: snapshot.yaw,
                    pitch: snapshot.pitch,
                    roll: snapshot.roll,
                    eyeOpenness: snapshot.eyeOpenness
                )
            )
            if case .failed(let reason) = livenessPhase {
                statusMessage = reason
                flow = .idle
                stopCaptureIfNeeded()
                return
            }
            guard livenessPhase == .passed else { return }
        }

        guard let latestProbe else { return }
        let decision = MatchPolicy.decide(
            probe: latestProbe,
            profiles: library.profiles,
            threshold: settingsStore.settings.similarityThreshold
        )
        matchDecision = decision
        settingsStore.settings.lastResult = LastAuthResult(
            date: Date(),
            success: decision.accepted,
            method: .face,
            detail: decision.reason,
            similarity: decision.similarity
        )
        if decision.accepted {
            settingsStore.settings.successfulAuthentications += 1
        }
        statusMessage = decision.reason
        flow = .idle
        stopCaptureIfNeeded()
    }

    private func verifyWithTouchID() {
        guard settingsStore.settings.allowTouchID else { return }
        isTouchIDRunning = true
        touchIDMessage = ""
        Task {
            defer { isTouchIDRunning = false }
            do {
                try await biometricService.authenticate()
                touchIDMessage = "Touch ID verified for MacFace AI."
                settingsStore.settings.lastResult = LastAuthResult(
                    date: Date(),
                    success: true,
                    method: .touchID,
                    detail: touchIDMessage,
                    similarity: nil
                )
                settingsStore.settings.successfulAuthentications += 1
            } catch {
                touchIDMessage = error.localizedDescription
                settingsStore.settings.lastResult = LastAuthResult(
                    date: Date(),
                    success: false,
                    method: .touchID,
                    detail: touchIDMessage,
                    similarity: nil
                )
            }
        }
    }

    private func refreshPasswordStatus() {
        do {
            hasAppPassword = try passwordService.hasPassword()
        } catch {
            passwordMessage = "Could not read the app password from Keychain: \(error.localizedDescription)"
        }
    }

    private func saveAppPassword() {
        do {
            if hasAppPassword {
                try passwordService.change(
                    old: currentPassword,
                    new: newPassword,
                    confirmation: passwordConfirmation
                )
            } else {
                try passwordService.create(password: newPassword, confirmation: passwordConfirmation)
            }
            currentPassword = ""
            newPassword = ""
            passwordConfirmation = ""
            passwordMessage = hasAppPassword ? "App password changed." : "App password set."
            refreshPasswordStatus()
        } catch {
            passwordMessage = error.localizedDescription
        }
    }

    private func removeAppPassword() {
        do {
            guard try passwordService.verify(currentPassword) else {
                passwordMessage = "The current app password is incorrect."
                return
            }
            try passwordService.delete()
            currentPassword = ""
            newPassword = ""
            passwordConfirmation = ""
            hasAppPassword = false
            passwordMessage = "App password removed."
        } catch {
            passwordMessage = error.localizedDescription
        }
    }

    private func deletePendingProfile() {
        guard let pendingDelete else { return }
        do {
            try library.delete(id: pendingDelete.id)
            statusMessage = "Deleted \(pendingDelete.displayName)'s face profile."
        } catch {
            statusMessage = "Could not delete the profile: \(error.localizedDescription)"
        }
        self.pendingDelete = nil
    }
}
