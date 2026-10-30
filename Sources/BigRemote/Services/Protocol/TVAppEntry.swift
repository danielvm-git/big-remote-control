// story: e09s03 e10s01
import Foundation

/// An app the TV reports (Sony `getApplicationList`, LG `listLaunchPoints`).
/// `id` is what the launch call takes: a Sony URI or a webOS app id.
struct TVAppEntry: Sendable, Equatable {
    var title: String
    var id: String

    /// Catalogue names are Samsung's ("HBO Max"); other TVs can use shorter titles ("Max").
    static func match(_ name: String, in apps: [TVAppEntry]) -> TVAppEntry? {
        let wanted = squash(name)
        guard !wanted.isEmpty else { return nil }
        if let exact = apps.first(where: { squash($0.title) == wanted }) { return exact }
        return apps.first { app in
            let title = squash(app.title)
            return title.count >= 3 && (title.contains(wanted) || wanted.hasSuffix(title))
        }
    }

    private static func squash(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(Character.init))
    }
}
