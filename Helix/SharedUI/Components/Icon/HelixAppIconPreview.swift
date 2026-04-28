import SwiftUI

struct HelixAppIconPreview: View {
    var body: some View {
        VStack(spacing: 32) {
            HStack(spacing: 32) {
                VStack(spacing: 16) {
                    HelixMark()
                        .frame(width: 180, height: 180)
                    Text("Mark only")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 16) {
                    HelixIconBezel(
                        backgroundColor: .white,
                        borderColor: Color.black.opacity(0.08),
                        showInnerHighlight: false,
                        showOuterShadow: true
                    ) {
                        HelixMark()
                    }
                    .frame(width: 180, height: 180)
                    Text("Light bezel")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 32) {
                VStack(spacing: 16) {
                    HelixIconBezel(
                        backgroundColor: .white,
                        borderColor: Color.black.opacity(0.08),
                        showInnerHighlight: false,
                        showOuterShadow: false
                    ) {
                        HelixMark()
                    }
                    .frame(width: 72, height: 72)
                    Text("Micro test")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 16) {
                    HelixIconBezel(
                        backgroundColor: HelixColor.background,
                        borderColor: Color.white.opacity(0.04),
                        showInnerHighlight: true,
                        showOuterShadow: false
                    ) {
                        HelixMark()
                    }
                    .frame(width: 180, height: 180)
                    Text("Dark bezel")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(40)
        .background(Color.gray.opacity(0.10))
    }
}

#Preview("Helix Icon System") {
    HelixAppIconPreview()
}
