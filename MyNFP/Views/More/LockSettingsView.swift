import SwiftUI

struct LockSettingsView: View {
    @Environment(AppLock.self) private var lock
    @State private var settingPIN = false
    @State private var confirmRemove = false

    var body: some View {
        @Bindable var lock = lock
        Form {
            Section {
                if lock.isEnabled {
                    Label("Code-Sperre ist aktiv", systemImage: "lock.fill").foregroundStyle(Theme.infertile)
                    Button("Code ändern") { settingPIN = true }
                    Button("Code-Sperre deaktivieren", role: .destructive) { confirmRemove = true }
                } else {
                    Button("Code-Sperre aktivieren") { settingPIN = true }
                }
            } footer: {
                Text("Schütze dein iPhone zusätzlich mit einer Bildschirmsperre. Die Code-Sperre verhindert, dass jemand mit Zugriff auf dein entsperrtes iPhone deine Zyklusdaten ansieht oder ändert.")
            }

            if lock.isEnabled {
                Section {
                    if lock.canUseBiometrics {
                        Toggle("Mit \(lock.biometryName) entsperren", isOn: $lock.biometricsEnabled)
                    }
                    Picker("Sperren", selection: $lock.lockDelaySeconds) {
                        Text("sofort").tag(0)
                        Text("nach 1 Minute").tag(60)
                        Text("nach 5 Minuten").tag(300)
                        Text("nach 15 Minuten").tag(900)
                    }
                }
            }
        }
        .navigationTitle("Code-Sperre")
        .sheet(isPresented: $settingPIN) { SetPINView() }
        .confirmationDialog("Code-Sperre deaktivieren?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Deaktivieren", role: .destructive) { lock.removePIN() }
        }
    }
}

struct SetPINView: View {
    @Environment(AppLock.self) private var lock
    @Environment(\.dismiss) private var dismiss
    @State private var first: String?
    @State private var pin = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(first == nil ? "Neuen Code eingeben (4–6 Ziffern)" : "Code wiederholen")
                    .font(.headline)
                PINDots(count: pin.count, maxCount: 6)
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                PINPad(pin: $pin, maxLength: 6) {
                    submit()
                }
                Button("Bestätigen") { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(pin.count < 4)
            }
            .padding()
            .navigationTitle("Code festlegen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
        }
    }

    private func submit() {
        guard pin.count >= 4 else { return }
        if let f = first {
            if f == pin {
                lock.setPIN(pin)
                dismiss()
            } else {
                error = "Die Codes stimmen nicht überein."
                first = nil
                pin = ""
            }
        } else {
            first = pin
            pin = ""
            error = nil
        }
    }
}

struct PINDots: View {
    let count: Int
    let maxCount: Int

    var body: some View {
        HStack(spacing: 14) {
            ForEach(0..<maxCount, id: \.self) { i in
                Circle()
                    .fill(i < count ? Color.primary : Color.clear)
                    .overlay(Circle().stroke(Color.primary, lineWidth: 1.5))
                    .frame(width: 14, height: 14)
            }
        }
        .accessibilityLabel("\(count) Ziffern eingegeben")
    }
}

struct PINPad: View {
    @Binding var pin: String
    let maxLength: Int
    var onComplete: () -> Void = {}
    var extraButton: AnyView? = nil

    var body: some View {
        let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
        VStack(spacing: 14) {
            ForEach(0..<3, id: \.self) { r in
                HStack(spacing: 22) {
                    ForEach(0..<3, id: \.self) { c in key(keys[r * 3 + c]) }
                }
            }
            HStack(spacing: 22) {
                if let extraButton { extraButton.frame(width: 72, height: 72) } else { Color.clear.frame(width: 72, height: 72) }
                key("0")
                Button {
                    if !pin.isEmpty { pin.removeLast() }
                } label: {
                    Image(systemName: "delete.left").font(.title2).frame(width: 72, height: 72)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Löschen")
            }
        }
    }

    private func key(_ k: String) -> some View {
        Button {
            guard pin.count < maxLength else { return }
            pin.append(k)
            if pin.count == maxLength { onComplete() }
        } label: {
            Text(k)
                .font(.system(size: 30, weight: .regular, design: .rounded))
                .frame(width: 72, height: 72)
                .background(Circle().fill(Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
    }
}

/// Sperrbildschirm
struct LockScreenView: View {
    @Environment(AppLock.self) private var lock
    @State private var pin = ""
    @State private var wrong = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "lock.fill").font(.system(size: 40)).foregroundStyle(Theme.accent)
            Text("Code eingeben").font(.title3.weight(.semibold))
            PINDots(count: pin.count, maxCount: 6)
                .modifier(Shake(animatableData: wrong ? 1 : 0))
            if lock.isLockedOut {
                Text("Zu viele Fehlversuche. Bitte kurz warten.").font(.footnote).foregroundStyle(.red)
            }
            PINPad(pin: $pin, maxLength: 6, onComplete: tryUnlock,
                   extraButton: lock.biometricsEnabled ? AnyView(Button {
                       Task { await lock.unlockWithBiometrics() }
                   } label: {
                       Image(systemName: lock.biometryType == .touchID ? "touchid" : "faceid").font(.title)
                   }.buttonStyle(.plain)) : nil)
            Button("OK") { tryUnlock() }
                .disabled(pin.count < 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .task { await lock.unlockWithBiometrics() }
        .onChange(of: pin) { _, new in
            // 4-stellige Codes ohne „OK“ entsperren
            if new.count >= 4, lock.verify(new) { tryUnlock() }
        }
    }

    private func tryUnlock() {
        if !lock.unlock(with: pin) {
            withAnimation(.default) { wrong.toggle() }
            pin = ""
        }
    }
}

struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 4), y: 0))
    }
}
