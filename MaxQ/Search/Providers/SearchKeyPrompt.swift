//
//  SearchKeyPrompt.swift
//  Max Q
//
//  What the results page shows where web results, pictures or videos would be when there's no
//  search key: what the key is for, the way to add one, and the same search on DuckDuckGo's own
//  page meanwhile.
//

import SwiftUI

struct SearchKeyPrompt: View {
    @Bindable var browser: BrowserModel
    /// DuckDuckGo's own page for the search.
    let site: URL?
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Web results need a search key")
                .font(.system(size: 19, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(Theme.textPrimary)
            Text("Max Q shows web results, pictures and videos from the Brave Search API, with your own key, which Brave gives with a free account. Until there's one, this search opens on DuckDuckGo.")
                .font(.system(size: 14.5))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Add a Search Key") {
                    SettingsRouter.shared.section = .general
                    openSettings()
                }
                .pill(.primary, size: .small)
                if let site {
                    Button("Open on DuckDuckGo") { openFromResults(site, browser: browser) }
                        .pill(.outline, size: .small)
                }
            }
            .padding(.top, 6)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: 560, alignment: .leading)
    }
}
