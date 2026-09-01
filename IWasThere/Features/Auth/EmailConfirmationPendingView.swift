import SwiftUI

struct EmailConfirmationPendingView: View {
    @Bindable var auth: AuthSession

    var body: some View {
        ZStack {
            StadiumAuthBackground()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "envelope.badge")
                    .font(.system(size: 48))
                    .foregroundStyle(DesignTokens.accent)

                VStack(spacing: 10) {
                    Text("Confirm your email")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(DesignTokens.primaryText)

                    Text("We sent a confirmation link to")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.secondaryText)

                    if let email = auth.pendingSignUpEmail {
                        Text(email)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DesignTokens.primaryText)
                            .multilineTextAlignment(.center)
                    }

                    Text("Open the link in your email to finish creating your account. The app will continue automatically, or tap below once you've confirmed.")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .frame(maxWidth: 420)

                if let error = auth.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.accent)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                if let info = auth.infoMessage {
                    Text(info)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                VStack(spacing: 12) {
                    Button {
                        Task { await auth.checkEmailConfirmation() }
                    } label: {
                        HStack {
                            if auth.isLoading {
                                ProgressView().tint(.white)
                            }
                            Text("I've confirmed my email")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(DesignTokens.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(auth.isLoading)

                    Button("Back to sign in") {
                        auth.cancelPendingSignUp()
                    }
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.secondaryText)
                }
                .frame(maxWidth: 420)
                .padding(.horizontal, 28)

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}
