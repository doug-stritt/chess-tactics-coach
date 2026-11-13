import XCTest

final class GameplayTests: XCTestCase {
    func testPlayAgainstComputerUndoAndRestart() {
        let app = XCUIApplication()
        app.launch()
        let status = app.staticTexts["game-status"]
        waitForTurn(status)
        let pawn = app.buttons["square-e2"]
        XCTAssertTrue(pawn.label.contains("white Pawn"))
        pawn.tap()
        XCTAssertEqual(app.buttons["square-e4"].value as? String, "Legal destination")
        app.buttons["square-e4"].tap()
        let list = app.staticTexts["move-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        waitForTurn(status)
        XCTAssertTrue(app.buttons["square-e4"].label.contains("white Pawn"))
        XCTAssertTrue(list.label.hasPrefix("1. e4 "))
        XCTAssertGreaterThan(list.label.split(separator: " ").count, 2)
        app.buttons["Undo turn"].tap()
        waitForTurn(status)
        XCTAssertTrue(pawn.label.contains("white Pawn"))
        XCTAssertFalse(list.exists)
        app.buttons["square-d2"].tap()
        app.buttons["square-d4"].tap()
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        waitForTurn(status)
        app.buttons["New game"].tap()
        app.buttons["Play as White"].tap()
        waitForTurn(status)
        XCTAssertTrue(app.buttons["square-d2"].label.contains("white Pawn"))
        XCTAssertFalse(list.exists)
    }

    func testDragLegalAndIllegalDrops() {
        let app = XCUIApplication()
        app.launch()
        let status = app.staticTexts["game-status"]
        waitForTurn(status)
        let pawn = app.buttons["square-e2"]
        pawn.press(forDuration: 0.08, thenDragTo: app.buttons["square-e5"])
        XCTAssertTrue(pawn.label.contains("white Pawn"))
        XCTAssertFalse(app.staticTexts["move-list"].exists)
        pawn.press(forDuration: 0.08, thenDragTo: app.staticTexts["Moves"])
        XCTAssertTrue(pawn.label.contains("white Pawn"))
        XCTAssertFalse(app.staticTexts["move-list"].exists)
        let bishop = app.buttons["square-f1"]
        bishop.press(forDuration: 0.08, thenDragTo: app.buttons["square-b5"])
        XCTAssertTrue(bishop.label.contains("white Bishop"))
        XCTAssertFalse(app.staticTexts["move-list"].exists)
        let destination = app.buttons["square-e4"]
        pawn.press(forDuration: 0.08, thenDragTo: destination)
        let list = app.staticTexts["move-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        waitForTurn(status)
        XCTAssertTrue(destination.label.contains("white Pawn"))
        XCTAssertGreaterThan(list.label.split(separator: " ").count, 2)
    }

    func testPlayingBlackFlipsBoardAndKeepsWhiteOpeningOnUndo() {
        let app = XCUIApplication()
        app.launch()
        let status = app.staticTexts["game-status"]
        waitForTurn(status)
        app.buttons["New game"].tap()
        app.buttons["Play as Black"].tap()
        let list = app.staticTexts["move-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        waitForTurn(status)
        let opening = list.label
        XCTAssertEqual(opening.split(separator: " ").count, 2)
        // A White opening in the center can pin a pawn on some lines.
        // Use an outside pawn whose one-square move is available after any opening.
        let pawn = app.buttons["square-a7"]
        let target = app.buttons["square-a6"]
        XCTAssertTrue(pawn.label.contains("black Pawn"))
        XCTAssertGreaterThan(pawn.frame.midY, target.frame.midY)
        XCTAssertGreaterThan(app.buttons["square-a7"].frame.midX, app.buttons["square-h7"].frame.midX)
        XCTAssertFalse(app.buttons["Undo turn"].isEnabled)
        pawn.press(forDuration: 0.08, thenDragTo: target)
        waitForTurn(status)
        XCTAssertTrue(target.label.contains("black Pawn"))
        XCTAssertTrue(list.label.contains("a6"))
        app.buttons["Undo turn"].tap()
        waitForTurn(status)
        XCTAssertEqual(list.label, opening)
        XCTAssertTrue(pawn.label.contains("black Pawn"))
    }

    func testPromotionPickerAndChoice() {
        let app = XCUIApplication()
        app.launchArguments.append("--test-promotion")
        app.launch()
        waitForTurn(app.staticTexts["game-status"])
        let pawn = app.buttons["square-a7"]
        let destination = app.buttons["square-a8"]
        pawn.tap()
        destination.tap()
        XCTAssertTrue(app.staticTexts["Promote pawn"].waitForExistence(timeout: 5))
        for (piece, name) in [("q", "Queen"), ("r", "Rook"), ("b", "Bishop"), ("n", "Knight")] {
            XCTAssertEqual(app.buttons["promote-\(piece)"].label, name)
        }
        app.buttons["Cancel"].tap()
        XCTAssertTrue(pawn.label.contains("white Pawn"))
        pawn.press(forDuration: 0.08, thenDragTo: destination)
        app.buttons["promote-n"].tap()
        let draw = NSPredicate(format: "label == %@", "Draw · Insufficient material")
        expectation(for: draw, evaluatedWith: app.staticTexts["game-status"])
        waitForExpectations(timeout: 5)
        XCTAssertTrue(destination.label.contains("white Knight"))
    }

    private func waitForTurn(_ status: XCUIElement) {
        let predicate = NSPredicate(format: "label == %@", "Your move")
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: status)], timeout: 20)
        XCTAssertEqual(result, .completed)
    }
}
