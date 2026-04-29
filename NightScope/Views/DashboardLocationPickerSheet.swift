#if os(macOS)
import SwiftUI
import CoreLocation

struct DashboardLocationPickerSheet: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var isPresented: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header
            content
        }
        .padding(Spacing.md)
        .frame(minWidth: 520, minHeight: 420)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("複数地点ダッシュボード"))
                    .font(.title2.bold())
                Text(L10n.tr("6件まで選択できます"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            (Text(L10n.format("%lld/%lld", viewModel.selectedIDs.count, DashboardViewModel.maxSelection))
            + Text(" ")
            + Text(L10n.tr("選択中")))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button(L10n.tr("閉じる")) {
                close()
            }

            Button(L10n.tr("完了")) {
                close()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.availableFavorites.isEmpty {
            ContentUnavailableView(
                L10n.tr("お気に入り地点がありません"),
                systemImage: "star",
                description: Text(L10n.tr("メインウィンドウのサイドバーから追加してください"))
            )
        } else {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                List {
                    ForEach(viewModel.availableFavorites) { favorite in
                        Toggle(isOn: selectionBinding(for: favorite.id)) {
                            DashboardLocationPickerRow(
                                favorite: favorite,
                                accessibilityHint: !viewModel.selectedIDs.contains(favorite.id) && !viewModel.canSelectMore
                                    ? L10n.tr("選択上限に達しました")
                                    : nil
                            )
                        }
                        .toggleStyle(.checkbox)
                        .disabled(!viewModel.selectedIDs.contains(favorite.id) && !viewModel.canSelectMore)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 300)

                if viewModel.selectedIDs.count == DashboardViewModel.maxSelection {
                    Text(L10n.tr("これ以上選択できません"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func close() {
        isPresented = false
        dismiss()
    }

    private func selectionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { viewModel.selectedIDs.contains(id) },
            set: { newValue in
                let isSelected = viewModel.selectedIDs.contains(id)
                guard newValue != isSelected else { return }
                viewModel.toggleSelection(id)
            }
        )
    }
}

private struct DashboardLocationPickerRow: View {
    let favorite: FavoriteLocation
    let accessibilityHint: String?

    var body: some View {
        Group {
            SelectedLocationSummaryContent(
                locationName: favorite.name,
                coordinate: CLLocationCoordinate2D(latitude: favorite.latitude, longitude: favorite.longitude),
                titleFont: .body,
                coordinateFont: .caption2,
                showsAccentIcon: false
            )
            .padding(.vertical, 2)
        }
        .modifier(DashboardAccessibilityHintModifier(hint: accessibilityHint))
    }
}

private struct DashboardAccessibilityHintModifier: ViewModifier {
    let hint: String?

    func body(content: Content) -> some View {
        if let hint {
            content.accessibilityHint(Text(hint))
        } else {
            content
        }
    }
}
#endif
