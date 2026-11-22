import Foundation
import SwiftUI

/// One whitespace-separated piece of text, e.g. `sentence.` — punctuation stays attached,
/// so joining tokens with spaces gives back readable text.
struct WordToken: Identifiable, Hashable {
    let id: Int
    let text: String
    /// The whitespace after it (spaces or line breaks), so the original text can be rebuilt exactly.
    var trailing = ""
    /// Whether this token differs from the user's original text (for highlighting corrections).
    var changed = false

    /// The word without surrounding punctuation, for looking up meanings: `"chase."` → `chase`.
    var bare: String {
        text.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols)
            .subtracting(CharacterSet(charactersIn: "'’-")))
    }

    var isWord: Bool { bare.contains { $0.isLetter } }
}

enum WordTokens {
    static func split(_ text: String) -> [WordToken] {
        var tokens: [WordToken] = []
        var word = "", space = ""
        func flush() {
            if !word.isEmpty { tokens.append(WordToken(id: tokens.count, text: word, trailing: space)) }
            word = ""; space = ""
        }
        for character in text {
            if character.isWhitespace {
                space.append(character)
            } else {
                if !space.isEmpty { flush() }
                word.append(character)
            }
        }
        flush()
        return tokens
    }

    /// Splits `revised` into tokens and marks the ones that aren't in `original` (word-level diff).
    static func diff(original: String, revised: String) -> [WordToken] {
        let old = split(original).map { normalize($0.text) }
        var new = split(revised)
        let newKeys = new.map { normalize($0.text) }

        // Longest common subsequence: tokens in it are unchanged, everything else is new or edited.
        let n = old.count, m = newKeys.count
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = old[i] == newKeys[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var i = 0, j = 0
        while j < m {
            if i < n, old[i] == newKeys[j] {
                i += 1; j += 1
            } else if i < n, lcs[i + 1][j] >= lcs[i][j + 1] {
                i += 1
            } else {
                new[j].changed = true
                j += 1
            }
        }
        return new
    }

    /// Case and punctuation changes count as changes; curly vs. straight quotes don't.
    private static func normalize(_ token: String) -> String {
        token.replacingOccurrences(of: "’", with: "'")
    }
}

/// Lays out views left to right, wrapping to new lines — like words in a paragraph.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
