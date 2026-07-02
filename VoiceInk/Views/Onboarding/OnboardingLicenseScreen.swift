import SwiftUI

struct OnboardingLicenseScreen: View {
    @ObservedObject var licenseViewModel: LicenseViewModel

    let onBack: () -> Void
    let onStartTrial: () -> Void
    let onActivate: () -> Void
    let onFinish: () -> Void

    var body: some View {
        OnboardingStepScreen(
            systemImage: "checkmark.seal.fill",
            title: "Local Fork Ready",
            subtitle: "This fork does not require license activation.",
            contentMaxWidth: 560
        ) {
            OnboardingLocalForkCard()
        } bottomBar: {
            OnboardingBottomBar(
                leadingTitle: "Back",
                primaryTitle: "Finish Onboarding",
                isPrimaryEnabled: true,
                onLeading: onBack,
                onPrimary: onFinish
            )
        }
    }
}

private struct OnboardingLocalForkCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("All local features are unlocked.", systemImage: "checkmark.seal.fill")
                .font(.headline)

            Text("VoiceInk will not contact a licensing server for activation or validation.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppMaterialCardBackground(cornerRadius: 14))
    }
}
