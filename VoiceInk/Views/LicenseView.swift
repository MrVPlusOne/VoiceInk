import SwiftUI

struct LicenseView: View {
    var body: some View {
        VStack(spacing: 15) {
            Text("Local Fork")
                .font(.headline)
            
            Text("License activation is disabled for this fork.")
                .foregroundColor(AppTheme.Status.positive)
                .font(.caption)
        }
        .padding()
    }
}

struct LicenseView_Previews: PreviewProvider {
    static var previews: some View {
        LicenseView()
    }
}
