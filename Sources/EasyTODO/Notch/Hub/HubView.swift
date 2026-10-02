import SwiftUI

struct HubView: View {
    @State private var selectedModule: HubModule = .ddl

    var body: some View {
        VStack(spacing: 0) {
            moduleStrip

            moduleContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var moduleStrip: some View {
        HStack(spacing: 6) {
            ForEach(HubModule.allCases) { module in
                Button {
                    selectedModule = module
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: module.systemImage)
                        Text(module.title)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        selectedModule == module
                            ? Color.white
                            : Color.white.opacity(0.55)
                    )
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background {
                        if selectedModule == module {
                            Capsule()
                                .fill(Color.white.opacity(0.14))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 40)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var moduleContent: some View {
        switch selectedModule {
        case .ddl:
            DDLModuleView()

        case .calendar:
            CalendarModuleView()

        case .music:
            placeholder(
                title: "Music",
                symbol: "music.note",
                subtitle: "Now playing"
            )

        case .shelf:
            placeholder(
                title: "Shelf",
                symbol: "tray",
                subtitle: "File shelf"
            )
        }
    }

    private func placeholder(
        title: String,
        symbol: String,
        subtitle: String
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))

            Text(title)
                .font(.system(size: 15, weight: .semibold))

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
