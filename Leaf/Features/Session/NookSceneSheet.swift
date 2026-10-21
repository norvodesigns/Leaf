import SwiftUI

/// Choosing the session's scene. The change shows at once behind the sheet. Light only: the room's sound is chosen
/// separately (`AmbienceSheet`), so picking the rain scene never starts the rain.
struct NookSceneSheet: View {
    @AppStorage(NookScene.storageKey) private var selection: NookScene = .lamp
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Space.m, alignment: .top), count: typeSize.isAccessibilitySize ? 2 : 4)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    LazyVGrid(columns: columns, spacing: Space.l) {
                        ForEach(NookScene.allCases) { scene in
                            card(scene)
                        }
                    }
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(selection.blurb)
                            .leafStyle(.uiBody)
                            .contentTransition(.opacity)
                        Text("Scenes are light only and hold still while you pause. Sound is separate: choose it under Ambience.")
                            .leafStyle(.caption)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Space.margin)
                .padding(.vertical, Space.s)
            }
            .paperBackground()
            .navigationTitle("Scene")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        Haptics.shared.tap()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.paper)
    }

    private func card(_ scene: NookScene) -> some View {
        let isOn = selection == scene
        return Button {
            guard !isOn else { return }
            Haptics.shared.selection()
            selection = scene
        } label: {
            VStack(spacing: Space.s) {
                NookSceneThumbnail(scene: scene, isSelected: isOn)
                Text(scene.name)
                    .leafStyle(.ui, color: isOn ? Color.accent : nil)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(scene.name)
        .accessibilityHint(scene.blurb)
        .accessibilityAddTraits(isOn ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }
}

#Preview("Scene sheet") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            NookSceneSheet()
        }
}
