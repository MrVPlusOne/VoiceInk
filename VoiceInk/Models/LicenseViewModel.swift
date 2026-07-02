import Foundation

@MainActor
class LicenseViewModel: ObservableObject {
    enum LicenseState: Equatable {
        case unlicensed
        case trial(daysRemaining: Int)
        case trialExpired
        case licensed
    }

    @Published private(set) var licenseState: LicenseState = .unlicensed
    @Published var licenseKey: String = ""
    @Published var isValidating = false
    @Published var validationMessage: String?
    @Published var validationSuccess: Bool = false
    @Published private(set) var activationsLimit: Int = 0

    init() {
        unlockLocalFork()
    }

    func startTrial() {
        unlockLocalFork()
        NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
        requestLicenseCelebration()
    }

    private func unlockLocalFork() {
        licenseState = .licensed
        licenseKey = String(localized: "Local Fork")
        isValidating = false
        validationSuccess = true
        activationsLimit = 0
    }

    var isLicensed: Bool {
        true
    }
    
    var canUseApp: Bool {
        true
    }

    var usageRestrictionMessage: String? {
        nil
    }
    
    func validateLicense() async {
        isValidating = true
        completeSuccessfulValidation(message: String(localized: "This fork does not require license activation."))
        isValidating = false
    }

    private func completeSuccessfulValidation(message: String) {
        unlockLocalFork()
        validationMessage = message
        NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
        requestLicenseCelebration()
    }

    private func requestLicenseCelebration() {
        NotificationCenter.default.post(name: .licenseCelebrationRequested, object: nil)
    }
    
    func removeLicense() {
        unlockLocalFork()
        validationMessage = String(localized: "This fork stays unlocked locally.")
        NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
    }
}
