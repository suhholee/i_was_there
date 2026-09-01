import SwiftUI

struct SignInView: View {
    @Bindable var auth: AuthSession
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false

    var body: some View {
        ZStack {
            StadiumAuthBackground()

            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 22) {
                        header

                        if !SupabaseConfig.isConfigured {
                            configBanner
                        }

                        formFields

                        if let error = auth.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(DesignTokens.accent)
                                .multilineTextAlignment(.center)
                        }

                        if let info = auth.infoMessage {
                            Text(info)
                                .font(.caption)
                                .foregroundStyle(DesignTokens.secondaryText)
                                .multilineTextAlignment(.center)
                        }

                        primaryButton
                        toggleModeButton
                    }
                    .padding(.horizontal, 28)
                    .frame(maxWidth: 420)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "baseball.fill")
                .font(.system(size: 36))
                .foregroundStyle(DesignTokens.accent)
                .shadow(color: DesignTokens.accent.opacity(0.45), radius: 12, y: 4)

            Text("#iWasThere")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(DesignTokens.primaryText)

            Text("Hey, I was there at that game")
                .font(.title3.weight(.semibold))
                .foregroundStyle(DesignTokens.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 8)
    }

    private var placeholderColor: Color {
        DesignTokens.secondaryText.opacity(0.85)
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Email")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.secondaryText)
            authField(placeholder: "you@example.com", text: $email, isSecure: false)

            Text("Password")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.secondaryText)
            authField(
                placeholder: "At least 6 characters",
                text: $password,
                isSecure: true
            )
        }
    }

    private func authField(placeholder: String, text: Binding<String>, isSecure: Bool) -> some View {
        ZStack(alignment: .leading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.body)
                    .foregroundStyle(placeholderColor)
                    .allowsHitTesting(false)
            }

            if isSecure {
                SecureField("", text: text)
                    .textContentType(isSignUp ? .newPassword : .password)
            } else {
                TextField("", text: text)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
            }
        }
        .font(.body)
        .foregroundStyle(DesignTokens.primaryText)
        .tint(DesignTokens.primaryText)
        .padding(12)
        .background(fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var fieldBackground: some ShapeStyle {
        DesignTokens.surface.opacity(0.92)
    }

    private var primaryButton: some View {
        Button {
            Task {
                if isSignUp {
                    await auth.signUp(email: email, password: password)
                } else {
                    await auth.signIn(email: email, password: password)
                }
            }
        } label: {
            HStack {
                if auth.isLoading {
                    ProgressView().tint(.white)
                }
                Text(isSignUp ? "Create account" : "Sign in")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(primaryButtonColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: primaryButtonColor.opacity(0.35), radius: 10, y: 4)
        }
        .disabled(!SupabaseConfig.isConfigured || auth.isLoading)
    }

    private var primaryButtonColor: Color {
        isSignUp ? DesignTokens.accent : DesignTokens.authSignInBlue
    }

    private var toggleModeButton: some View {
        Button {
            isSignUp.toggle()
            auth.clearMessages()
        } label: {
            if isSignUp {
                Text("Already have an account? ")
                    .foregroundStyle(DesignTokens.secondaryText)
                + Text("Sign in")
                    .foregroundStyle(DesignTokens.authSignInBlue)
                    .fontWeight(.semibold)
            } else {
                Text("New here? ")
                    .foregroundStyle(DesignTokens.secondaryText)
                + Text("Create an account")
                    .foregroundStyle(DesignTokens.accent)
                    .fontWeight(.semibold)
            }
        }
        .font(.subheadline)
        .padding(.bottom, 24)
    }

    private var configBanner: some View {
        Text("Create IWasThere/Config/SupabaseConfig.plist (not the .example file) with your Supabase URL and anon key, then rebuild. See docs/BACKEND.md.")
            .font(.caption)
            .foregroundStyle(DesignTokens.accent)
            .multilineTextAlignment(.center)
    }
}
