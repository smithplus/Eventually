import XCTest
import Foundation
// QuickAddParser.swift is compiled directly into this test bundle (pure logic, no app host)

final class QuickAddParserTests: XCTestCase {

    // Fixed reference date: Saturday, 2026-05-30 (matches "today" in dev context)
    private var calendar: Calendar { Calendar(identifier: .gregorian) }

    private func refDate() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 30      // Saturday
        components.hour = 14
        return calendar.date(from: components)!
    }

    // MARK: - Plain title

    func testPlainTitle() {
        let r = QuickAddParser.parse("Comprar leche", referenceDate: refDate(), calendar: calendar)
        XCTAssertEqual(r.title, "Comprar leche")
        XCTAssertNil(r.listName)
        XCTAssertNil(r.dueDate)
    }

    // MARK: - List token

    func testListToken() {
        let r = QuickAddParser.parse("Review PR #Work", referenceDate: refDate(), calendar: calendar)
        XCTAssertEqual(r.title, "Review PR")
        XCTAssertEqual(r.listName, "Work")
    }

    func testListTokenInMiddle() {
        let r = QuickAddParser.parse("Llamar #Personal al dentista", referenceDate: refDate(), calendar: calendar)
        XCTAssertEqual(r.title, "Llamar al dentista")
        XCTAssertEqual(r.listName, "Personal")
    }

    func testLoneHashIsNotAList() {
        let r = QuickAddParser.parse("Comprar # leche", referenceDate: refDate(), calendar: calendar)
        XCTAssertNil(r.listName)
        XCTAssertEqual(r.title, "Comprar # leche")
    }

    // MARK: - Today / Tomorrow (Spanish + English)

    func testTodaySpanish() {
        let r = QuickAddParser.parse("Pagar luz hoy", referenceDate: refDate(), calendar: calendar)
        XCTAssertEqual(r.title, "Pagar luz")
        XCTAssertEqual(r.dueDate, calendar.startOfDay(for: refDate()))
    }

    func testTomorrowEnglish() {
        let r = QuickAddParser.parse("Standup tomorrow", referenceDate: refDate(), calendar: calendar)
        let expected = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: refDate()))
        XCTAssertEqual(r.dueDate, expected)
        XCTAssertEqual(r.title, "Standup")
    }

    func testMananaWithAccentInsensitive() {
        // "mañana" folded to "manana" must still match
        let r = QuickAddParser.parse("Enviar reporte mañana", referenceDate: refDate(), calendar: calendar)
        let expected = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: refDate()))
        XCTAssertEqual(r.dueDate, expected)
    }

    // MARK: - Weekdays

    func testNextWeekday() {
        // refDate is Saturday. "lunes" (Monday) → 2 days ahead → June 1
        let r = QuickAddParser.parse("Reunión lunes", referenceDate: refDate(), calendar: calendar)
        let monday = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: refDate()))
        XCTAssertEqual(r.dueDate, monday)
        XCTAssertEqual(r.title, "Reunión")
    }

    func testSameWeekdayGoesToNextWeek() {
        // refDate is Saturday. "sabado" → should be +7 days, not today
        let r = QuickAddParser.parse("Limpiar casa sabado", referenceDate: refDate(), calendar: calendar)
        let nextSat = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: refDate()))
        XCTAssertEqual(r.dueDate, nextSat)
    }

    // MARK: - Combined

    func testListAndDate() {
        let r = QuickAddParser.parse("Llamar al dentista #Salud mañana", referenceDate: refDate(), calendar: calendar)
        XCTAssertEqual(r.title, "Llamar al dentista")
        XCTAssertEqual(r.listName, "Salud")
        let expected = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: refDate()))
        XCTAssertEqual(r.dueDate, expected)
    }

    func testOnlyFirstDateWins() {
        // "hoy" consumed as date; "mañana" stays in title
        let r = QuickAddParser.parse("Tarea hoy mañana", referenceDate: refDate(), calendar: calendar)
        XCTAssertEqual(r.dueDate, calendar.startOfDay(for: refDate()))
        XCTAssertEqual(r.title, "Tarea mañana")
    }

    // MARK: - Explicit ! date markers

    private func today() -> Date { calendar.startOfDay(for: refDate()) }

    func testBangRelativeDaysSpanish() {
        let r = QuickAddParser.parse("Entregar informe !4dias", referenceDate: refDate(), calendar: calendar)
        XCTAssertEqual(r.title, "Entregar informe")
        XCTAssertEqual(r.dueDate, calendar.date(byAdding: .day, value: 4, to: today()))
    }

    func testBangRelativeWeeksSpanish() {
        let r = QuickAddParser.parse("Renovar !2semanas", referenceDate: refDate(), calendar: calendar)
        XCTAssertEqual(r.dueDate, calendar.date(byAdding: .day, value: 14, to: today()))
    }

    func testBangRelativeDaysEnglishAbbrev() {
        let r = QuickAddParser.parse("Ship build !3d", referenceDate: refDate(), calendar: calendar)
        XCTAssertEqual(r.title, "Ship build")
        XCTAssertEqual(r.dueDate, calendar.date(byAdding: .day, value: 3, to: today()))
    }

    func testBangMonths() {
        let r = QuickAddParser.parse("Revisión !1mes", referenceDate: refDate(), calendar: calendar)
        XCTAssertEqual(r.dueDate, calendar.date(byAdding: .month, value: 1, to: today()))
    }

    func testBangWord() {
        let r = QuickAddParser.parse("Pagar !manana", referenceDate: refDate(), calendar: calendar)
        XCTAssertEqual(r.dueDate, calendar.date(byAdding: .day, value: 1, to: today()))
    }

    func testBangTimeUnitResolvesToToday() {
        // Google Tasks stores date only, so !5min resolves to today.
        let r = QuickAddParser.parse("Llamar !5min", referenceDate: refDate(), calendar: calendar)
        XCTAssertEqual(r.dueDate, today())
        XCTAssertEqual(r.title, "Llamar")
    }

    func testBareNumberWordIsNotConsumed() {
        // "4 panes" must NOT be read as a date (only ! markers parse durations).
        let r = QuickAddParser.parse("Comprar 4 panes", referenceDate: refDate(), calendar: calendar)
        XCTAssertNil(r.dueDate)
        XCTAssertEqual(r.title, "Comprar 4 panes")
    }

    func testUnrecognizedBangStaysLiteral() {
        // !foo doesn't resolve → keep it in the title, don't silently drop it.
        let r = QuickAddParser.parse("Tarea !foo", referenceDate: refDate(), calendar: calendar)
        XCTAssertNil(r.dueDate)
        XCTAssertEqual(r.title, "Tarea !foo")
    }

    func testOnlyBangOrHashYieldsEmptyMarkers() {
        let r = QuickAddParser.parse("Solo titulo # !", referenceDate: refDate(), calendar: calendar)
        XCTAssertNil(r.dueDate)
        XCTAssertNil(r.listName)
        XCTAssertEqual(r.title, "Solo titulo # !")
    }
}
