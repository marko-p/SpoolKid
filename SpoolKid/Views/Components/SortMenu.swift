import SwiftUI

struct SortMenu<Option: SortOption & RawRepresentable, Footer: View>: View where Option.RawValue == String, Option.AllCases: RandomAccessCollection {
    var title: String = "Sort"
    var filtersActive: Bool = false
    let options: Option.Type
    @Binding var field: String
    @Binding var ascending: Bool
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        Menu {
            // Option rows + footer must always show text + icon, even when an
            // ancestor applies `.labelStyle(.iconOnly)` to the inline Sort button.
            // Scope the style to the content only — NOT the Menu — so the Menu's
            // own label inherits the ancestor style (icon-only inline; text when
            // nested as a "Sort" submenu inside the collapsed "…" menu).
            Group {
                SortOptionRows(options: options, field: $field, ascending: $ascending)
                footer()
            }
            .labelStyle(.titleAndIcon)
        } label: {
            if filtersActive {
                Label(title, systemImage: "arrow.up.arrow.down.circle.fill")
                    .foregroundStyle(Color.accentColor)
            } else {
                Label(title, systemImage: "arrow.up.arrow.down")
            }
        }
    }
}

extension SortMenu where Footer == EmptyView {
    init(title: String = "Sort", filtersActive: Bool = false, options: Option.Type, field: Binding<String>, ascending: Binding<Bool>) {
        self.title = title
        self.filtersActive = filtersActive
        self.options = options
        self._field = field
        self._ascending = ascending
        self.footer = { EmptyView() }
    }
}
