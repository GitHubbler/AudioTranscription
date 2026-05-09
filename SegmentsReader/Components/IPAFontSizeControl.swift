import SwiftUI

struct IPAFontSizeControl: View {
    @Binding var fontSize: Double

    var body: some View {
        HStack(spacing: 8) {
            Button {
                fontSize = max(Self.minimumSize, fontSize - 1)
            } label: {
                Image(systemName: "textformat.size.smaller")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help("Smaller IPA")

            Text("IPA \(Int(fontSize)) pt")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .center)

            Button {
                fontSize = min(Self.maximumSize, fontSize + 1)
            } label: {
                Image(systemName: "textformat.size.larger")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help("Larger IPA")
        }
        .controlSize(.small)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    private static let minimumSize = 8.0
    private static let maximumSize = 22.0
}
