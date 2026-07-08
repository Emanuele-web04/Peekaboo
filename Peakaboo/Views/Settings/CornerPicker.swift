import SwiftUI

struct CornerPicker: View {
    @Binding var selection: ScreenCorner

    var body: some View {
        VStack(spacing: 9) {
            HStack {
                cornerButton(.topLeft)
                Spacer()
                cornerButton(.topRight)
            }
            Spacer()
            Image(systemName: "display")
                .font(.system(size: 23, weight: .light))
                .foregroundStyle(.tertiary)
            Spacer()
            HStack {
                cornerButton(.bottomLeft)
                Spacer()
                cornerButton(.bottomRight)
            }
        }
        .padding(10)
        .frame(width: 230, height: 132)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.7)
        }
    }

    private func cornerButton(_ corner: ScreenCorner) -> some View {
        Button { selection = corner } label: {
            Circle()
                .fill(selection == corner ? Color.accentColor : Color.primary.opacity(0.12))
                .frame(width: 17, height: 17)
                .overlay {
                    Circle()
                        .stroke(selection == corner ? Color.accentColor.opacity(0.25) : .clear, lineWidth: 5)
                }
        }
        .buttonStyle(.plain)
        .help(corner.title)
        .accessibilityLabel(corner.title)
        .accessibilityAddTraits(selection == corner ? .isSelected : [])
    }
}
