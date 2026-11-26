import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let store: PRStore

    var body: some View {
        TabView {
            GeneralSettings(store: store)
                .tabItem { Label("General", systemImage: "gearshape") }
            AccountSettings(store: store)
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .frame(width: 500)
    }
}

private struct GeneralSettings: View {
    let store: PRStore
    @AppStorage(PRStore.intervalKey) private var interval = 60
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
        Form {
            Picker("Refresh Pull Requests:", selection: $interval) {
                Text("Every 30 seconds").tag(30)
                Text("Every minute").tag(60)
                Text("Every 2 minutes").tag(120)
                Text("Every 5 minutes").tag(300)
                Text("Every 10 minutes").tag(600)
            }
            LabeledContent("Startup:") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Open PullView at login", isOn: launchAtLogin)
                    if loginStatus == .requiresApproval {
                        Text("Allow PullView in System Settings > General > Login Items.")
                            .foregroundStyle(.secondary)
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    }
                    if let loginError {
                        Text(loginError).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .formStyle(.columns)
        .padding(20)
        .onChange(of: interval) { store.start() }
        .onAppear { loginStatus = SMAppService.mainApp.status }
    }

    /// Calls the service once per click and shows the resulting status, so a failure never toggles back and forth.
    private var launchAtLogin: Binding<Bool> {
        Binding {
            loginStatus == .enabled
        } set: { enabled in
            do {
                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                loginError = nil
            } catch {
                loginError = error.localizedDescription // e.g. running outside an app bundle
            }
            loginStatus = SMAppService.mainApp.status
        }
    }
}

private struct AccountSettings: View {
    let store: PRStore
    @AppStorage(TokenMode.key) private var mode = TokenMode.cli
    @State private var draft = ""
    @State private var saved = ""
    @State private var saveFailed = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Form {
            Picker("GitHub Token:", selection: $mode) {
                Text("From the GitHub CLI (gh auth token)").tag(TokenMode.cli)
                Text("Personal access token").tag(TokenMode.personal)
            }
            .pickerStyle(.radioGroup)

            if mode == .personal {
                SecureField("Token:", text: $draft, prompt: Text("ghp_…"))
                    .focused($fieldFocused)
                    .onSubmit(save)
                LabeledContent("") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("A classic token needs the repo and read:org scopes. PullView keeps it in your keychain.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                LabeledContent("") {
                    Text("Run gh auth login in Terminal to sign in. GH_TOKEN or GITHUB_TOKEN take precedence when set.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            LabeledContent("Status:") { status }
        }
        .formStyle(.columns)
        .padding(20)
        .onAppear { saved = Keychain.read() ?? ""; draft = saved }
        // Settings apply without a Save button: on Return, on leaving the field, and on closing the tab or window.
        .onChange(of: fieldFocused) { if !fieldFocused { save() } }
        .onDisappear(perform: save)
        .onChange(of: draft) { saveFailed = false }
        .onChange(of: mode) {
            saveFailed = false
            store.credentialsChanged()
        }
    }

    @ViewBuilder private var status: some View {
        if saveFailed {
            Label("Could not save the token to the keychain.", systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
        } else if store.isLoading {
            ProgressView().controlSize(.small)
        } else if let error = store.error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .fixedSize(horizontal: false, vertical: true)
        } else if let login = store.sections?.viewer?.login {
            Label("Signed in as \(login)", systemImage: "checkmark.circle.fill")
                .symbolRenderingMode(.multicolor)
        } else {
            Text("Not checked yet").foregroundStyle(.secondary)
        }
    }

    private func save() {
        // Trim into a local: assigning draft first would fire onChange(of: draft) and hide a failed save.
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value != saved else { return }
        saveFailed = !Keychain.write(value)
        if !saveFailed {
            saved = value
            draft = value
            store.credentialsChanged()
        }
    }
}
