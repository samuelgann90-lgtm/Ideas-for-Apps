import SwiftUI

struct ManualSearchView: View {
  @Binding var isPresented: Bool
  let onSearch: (String) -> Void

  @State private var searchText = ""
  @State private var suggestions: [String] = []
  @State private var isLoadingSuggestions = false
  @FocusState private var isSearchFocused: Bool

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        HStack(spacing: 10) {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(.secondary)

          TextField("e.g. Charizard ex, Pikachu VMAX", text: $searchText)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .focused($isSearchFocused)
            .submitLabel(.search)
            .onSubmit { performSearch() }

          if !searchText.isEmpty {
            Button {
              searchText = ""
              suggestions = []
            } label: {
              Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
            }
          }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding()

        if isLoadingSuggestions {
          ProgressView("Finding cards…")
            .font(.caption)
            .padding(.bottom, 8)
        }

        if !suggestions.isEmpty {
          List {
            Section("Suggestions") {
              ForEach(suggestions, id: \.self) { name in
                Button {
                  searchText = name
                  performSearch()
                } label: {
                  HStack {
                    Image(systemName: "sparkles")
                      .foregroundStyle(.yellow)
                    Text(name)
                      .foregroundStyle(.primary)
                  }
                }
              }
            }
          }
          .listStyle(.plain)
        } else if searchText.count >= 2 {
          ContentUnavailableView {
            Label("No suggestions yet", systemImage: "text.magnifyingglass")
          } description: {
            Text("Keep typing or press Search to look up \"\(searchText)\".")
          }
          .frame(maxHeight: 200)
        } else {
          Spacer()
          Text("Type at least 2 characters for Pokémon card name suggestions.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding()
          Spacer()
        }
      }
      .navigationTitle("Search by Name")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { isPresented = false }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Search", action: performSearch)
            .fontWeight(.semibold)
            .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .onAppear { isSearchFocused = true }
      .task(id: searchText) {
        await loadSuggestions()
      }
    }
  }

  private func performSearch() {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return }
    isPresented = false
    onSearch(query)
  }

  private func loadSuggestions() async {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard query.count >= 2 else {
      suggestions = []
      return
    }

    isLoadingSuggestions = true
    defer { isLoadingSuggestions = false }

    try? await Task.sleep(nanoseconds: 350_000_000)
    guard !Task.isCancelled else { return }

    let results = await PokemonTCGService.shared.suggestNames(matching: query)
    guard !Task.isCancelled else { return }
    suggestions = results
  }
}

#Preview {
  ManualSearchView(isPresented: .constant(true)) { _ in }
}
