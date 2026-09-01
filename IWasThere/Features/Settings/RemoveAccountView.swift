import SwiftUI
import SwiftData

struct RemoveAccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var acknowledged = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Text("Removing your account permanently deletes your profile, game diary, friends, and photos from our servers. This cannot be undone.")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.secondaryText)
            }

            Section {
                Button {
                    acknowledged.toggle()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: acknowledged ? "checkmark.square.fill" : "square")
                            .font(.title3)
                            .foregroundStyle(acknowledged ? DesignTokens.accent : DesignTokens.secondaryText)

                        Text("I understand my account and all associated data will be permanently deleted.")
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.primaryText)
                            .multilineTextAlignment(.leading)
                    }
                }
                .buttonStyle(.plain)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.loseRed)
                }
            }

            Section {
                Button(role: .destructive) {
                    Task { await removeAccount() }
                } label: {
                    HStack {
                        Spacer()
                        if isDeleting {
                            ProgressView()
                                .tint(DesignTokens.loseRed)
                        } else {
                            Text("Remove account")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(!acknowledged || isDeleting)
            }
        }
        .navigationTitle("Remove account")
        .navigationBarTitleDisplayMode(.inline)
        .tint(DesignTokens.primaryText)
        .toolbarBackground(DesignTokens.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func removeAccount() async {
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }

        do {
            try await AuthSession.shared.deleteAccount(modelContext: modelContext)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        RemoveAccountView()
    }
    .modelContainer(for: [UserProfile.self], inMemory: true)
}
