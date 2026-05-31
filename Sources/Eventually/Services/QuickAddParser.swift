import Foundation

/// Parses quick-add input like "Llamar al dentista #Work mañana"
/// into a structured task: title, optional list name, optional due date.
///
/// Supported inline tokens:
/// - `#listName`  → assigns the task to a list (matched case-insensitively elsewhere)
/// - date words   → Spanish & English: hoy/today, mañana/tomorrow, weekday names
struct QuickAddParser {

    struct Result: Equatable {
        var title: String
        var listName: String?
        var dueDate: Date?
    }

    /// Parse raw input into a structured result.
    /// - Parameters:
    ///   - input: the raw text the user typed
    ///   - referenceDate: "now" — injectable for deterministic tests
    ///   - calendar: calendar used for date math — injectable for tests
    static func parse(
        _ input: String,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Result {
        var tokens = input.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

        var listName: String?
        var dueDate: Date?
        var titleTokens: [String] = []

        for token in tokens {
            // List token: #Something
            if token.hasPrefix("#"), token.count > 1 {
                listName = String(token.dropFirst())
                continue
            }

            // Date token (consumes the word if recognized)
            if dueDate == nil, let date = dateFromToken(token, referenceDate: referenceDate, calendar: calendar) {
                dueDate = date
                continue
            }

            titleTokens.append(token)
        }

        _ = tokens // silence unused in case of future refactors

        let title = titleTokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return Result(title: title, listName: listName, dueDate: dueDate)
    }

    // MARK: - Date parsing

    /// Maps a single lowercased word to a date relative to `referenceDate`.
    /// Returns nil if the token is not a recognized date word.
    private static func dateFromToken(
        _ token: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> Date? {
        let word = token.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        let startOfToday = calendar.startOfDay(for: referenceDate)

        switch word {
        case "hoy", "today":
            return startOfToday
        case "manana", "tomorrow":
            return calendar.date(byAdding: .day, value: 1, to: startOfToday)
        default:
            break
        }

        // Weekday names (next occurrence, Spanish + English)
        if let target = weekdayIndex(for: word) {
            return nextWeekday(target, after: startOfToday, calendar: calendar)
        }

        return nil
    }

    /// 1 = Sunday ... 7 = Saturday (matches Calendar.component(.weekday))
    private static func weekdayIndex(for word: String) -> Int? {
        switch word {
        case "domingo", "sunday":      return 1
        case "lunes", "monday":        return 2
        case "martes", "tuesday":      return 3
        case "miercoles", "wednesday": return 4
        case "jueves", "thursday":     return 5
        case "viernes", "friday":      return 6
        case "sabado", "saturday":     return 7
        default:                       return nil
        }
    }

    /// Returns the next date (strictly after `date`) that falls on `weekday`.
    /// If today *is* that weekday, returns 7 days ahead (next week), not today.
    private static func nextWeekday(_ weekday: Int, after date: Date, calendar: Calendar) -> Date? {
        let current = calendar.component(.weekday, from: date)
        var delta = weekday - current
        if delta <= 0 { delta += 7 }
        return calendar.date(byAdding: .day, value: delta, to: date)
    }
}
