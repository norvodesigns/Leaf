import SwiftUI

/// Choosing the session's scene: system sheet glass at a medium detent, plain on top, then the realistic and the soft
/// scenes as cards, the change showing at once behind the sheet. Light only: the room's sound is chosen separately (`AmbienceSheet`), so picking the rain
/// scene never starts the rain.
struct NookSceneSheet: View {
    @AppStorage(NookScene.storageKey) private var selection: NookScene = .plain
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Canopy.Space.m, alignment: .top), count: typeSize.isAccessibilitySize ? 2 : 3)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Canopy.Space.xl) {
                    CanopyChip(NookScene.plain.name, systemImage: NookScene.plain.symbol, isSelected: selection == .plain) {
                        withAnimation(Canopy.Motion.snappy) { selection = .plain }
                    }
                    .accessibilityHint(NookScene.plain.blurb)
                    section("Realistic", scenes: NookScene.realistic)
                    section("Soft", scenes: NookScene.soft)
                    VStack(alignment: .leading, spacing: Canopy.Space.xs) {
                        Text(selection.blurb)
                            .canopyText(.body)
                            .contentTransition(.opacity)
                        Text("Scenes are pictures only and hold still while you pause. Sound is its own choice, under Ambience.")
                            .canopyText(.caption)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Canopy.Space.margin)
                .padding(.vertical, Canopy.Space.s)
            }
            .navigationTitle("Scene")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        CanopyFeel.play(.tap)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func section(_ title: String, scenes: [NookScene]) -> some View {
        VStack(alignment: .leading, spacing: Canopy.Space.s) {
            CanopyLabel(title)
            LazyVGrid(columns: columns, spacing: Canopy.Space.l) {
                ForEach(scenes) { scene in
                    card(scene)
                }
            }
        }
    }

    private func card(_ scene: NookScene) -> some View {
        let isOn = selection == scene
        return Button {
            guard !isOn else { return }
            CanopyFeel.play(.select)
            withAnimation(Canopy.Motion.snappy) { selection = scene }
        } label: {
            VStack(spacing: Canopy.Space.s) {
                NookSceneThumbnail(scene: scene, isSelected: isOn)
                Text(scene.name)
                    .canopyText(.callout, color: isOn ? CanopyAccent.forest.color : nil)
                    .fontWeight(isOn ? .semibold : .regular)
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
