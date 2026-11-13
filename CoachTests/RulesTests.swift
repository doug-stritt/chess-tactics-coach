import XCTest
import UIKit
@testable import ChessTacticsCoach

final class RulesTests: XCTestCase {
    private let engine = ChessEngine()

    private func position(_ fen: String? = nil, moves: [Move] = [], move: Move? = nil) async throws -> Position {
        let response = try await engine.run(.init(fen: fen, moves: moves, move: move))
        return try XCTUnwrap(response.board)
    }

    func testInitialPositionAndIllegalMove() async throws {
        let start = try await position()
        XCTAssertEqual(start.moves.count, 20)
        XCTAssertEqual(start.pieces.count, 32)
        do {
            _ = try await position(move: Move(from: "e2", to: "e5", promotion: nil, san: "e5"))
            XCTFail("Illegal move was accepted")
        } catch is ChessEngine.EngineError {}
    }

    func testCastlingEnPassantAndPromotion() async throws {
        let castle = "4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1"
        let afterCastle = try await play("O-O", in: castle)
        XCTAssertEqual(afterCastle.pieces["g1"], "K")
        XCTAssertEqual(afterCastle.pieces["f1"], "R")
        let attacked = try await position("4kr2/8/8/8/8/8/8/R3K2R w KQ - 0 1")
        XCTAssertFalse(attacked.moves.contains { $0.san == "O-O" })
        let afterCapture = try await play("exd6", in: "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
        XCTAssertNil(afterCapture.pieces["d5"])
        XCTAssertEqual(afterCapture.pieces["d6"], "P")
        let promotion = "4k3/P7/8/8/8/8/8/4K3 w - - 0 1"
        let beforePromotion = try await position(promotion)
        XCTAssertEqual(Set(beforePromotion.moves.compactMap(\.promotion)), ["q", "b", "r", "n"])
        let promoted = try await play("a8=N", in: promotion)
        XCTAssertEqual(promoted.pieces["a8"], "N")
    }

    func testMateStalemateAndDraws() async throws {
        let cases = [
            ("7k/6Q1/6K1/8/8/8/8/8 b - - 0 1", "Checkmate", true),
            ("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1", "Stalemate", false),
            ("4k3/8/8/8/8/8/8/4K3 w - - 0 1", "Draw · Insufficient material", false),
            ("4k3/8/8/8/8/8/8/R3K3 w - - 100 51", "Draw · Fifty-move rule", false)
        ]
        for (fen, ending, inCheck) in cases {
            let actual = try await position(fen)
            XCTAssertEqual(actual.ending, ending)
            XCTAssertEqual(actual.inCheck, inCheck)
        }
        let cycle = [
            Move(from: "g1", to: "f3", promotion: nil, san: "Nf3"),
            Move(from: "g8", to: "f6", promotion: nil, san: "Nf6"),
            Move(from: "f3", to: "g1", promotion: nil, san: "Ng1"),
            Move(from: "f6", to: "g8", promotion: nil, san: "Ng8")
        ]
        let repeated = try await position(moves: cycle + cycle)
        XCTAssertEqual(repeated.ending, "Draw · Threefold repetition")
    }

    func testComputerTakesMate() async throws {
        let fen = "6k1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 1"
        let response = try await engine.run(.init(action: "reply", fen: fen))
        XCTAssertEqual(response.reply?.san, "Re8#")
    }

    func testTacticsFindsFollowUpCaptureAndSuggestsBestMoveInQuietOpening() async throws {
        let fen = "4k3/8/8/8/3q4/2P5/3R4/4K3 w - - 0 1"
        let result = try await engine.run(.init(action: "tactics", fen: fen))
        let line = try XCTUnwrap(result.tactics?.first { $0.moves.first?.san == "Re2+" })
        XCTAssertEqual(line.moves.count, 3)
        XCTAssertEqual(line.moves.last?.san, "cxd4")
        let after = try await position(fen, moves: line.moves)
        XCTAssertEqual(after.pieces["d4"], "P")
        XCTAssertGreaterThan(line.evaluation, 0)
        XCTAssertGreaterThan(after.evaluation, 0)
        let opening = try await engine.run(.init(action: "tactics"))
        XCTAssertNotNil(result.bestLine)
        XCTAssertEqual(opening.tactics, [])
        let bestLine = try XCTUnwrap(opening.bestLine)
        XCTAssertEqual(bestLine.moves.count, 3)
        for (index, move) in bestLine.moves.enumerated() {
            let before = try await position(moves: Array(bestLine.moves.prefix(index)))
            XCTAssertTrue(before.moves.contains(move))
        }
        XCTAssertLessThan(abs(bestLine.evaluation), 150)
    }

    func testStockfishScoresQueenAdvantageFromEitherTurn() async throws {
        let whiteToMove = try await position("7k/8/8/8/8/8/4Q3/4K3 w - - 0 1")
        let blackToMove = try await position("7k/8/8/8/8/8/4Q3/4K3 b - - 0 1")
        XCTAssertGreaterThan(whiteToMove.evaluation, 300)
        XCTAssertGreaterThan(blackToMove.evaluation, 300)
    }

    func testWinningForkAndDiscoveredAttackAreLabeled() async throws {
        let fork = try await engine.run(.init(action: "tactics", fen: "3q3k/8/8/4N3/8/8/P7/4K3 w - - 0 1"))
        let forkLine = try XCTUnwrap(fork.tactics?.first { $0.moves.first?.san == "Nf7+" })
        XCTAssertTrue(forkLine.motifs.contains("Fork"))
        XCTAssertEqual(forkLine.moves.last?.san, "Nxd8")

        let discovered = try await engine.run(.init(action: "tactics", fen: "4k3/8/q7/8/8/8/4B3/4R1K1 w - - 0 1"))
        let discoveredLine = try XCTUnwrap(discovered.tactics?.first { $0.moves.first?.san == "Bd3+" })
        XCTAssertTrue(discoveredLine.motifs.contains("Discovered attack"))
        XCTAssertEqual(discoveredLine.moves.last?.san, "Bxa6")
    }

    func testChessFoxMotifsOnEngineLines() async throws {
        let cases = [
            ("4k3/8/4n3/8/8/8/8/R5K1 w - - 0 1", "a1e1", "Pin"),
            ("4q3/8/4k3/8/8/8/8/R5K1 w - - 0 1", "a1e1", "Skewer"),
            ("4k3/8/8/8/8/8/4B3/4R1K1 w - - 0 1", "e2b5", "Double check"),
            ("6k1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 1", "e1e8", "Back-rank mate"),
            ("4k3/P7/8/8/8/8/8/4K3 w - - 0 1", "a7a8r", "Underpromotion")
        ]
        for (fen, uci, motif) in cases {
            let response = try await engine.run(.init(action: "line", fen: fen, line: [uci]))
            XCTAssertTrue(response.bestLine?.motifs.contains(motif) == true, motif)
        }
    }

    @MainActor
    func testAllPieceImagesAreBundled() {
        for color in ["w", "b"] {
            for piece in ["K", "Q", "R", "B", "N", "P"] {
                XCTAssertNotNil(UIImage(named: color + piece), color + piece)
            }
        }
    }

    private func play(_ san: String, in fen: String) async throws -> Position {
        let before = try await position(fen)
        return try await position(fen, move: XCTUnwrap(before.moves.first { $0.san == san }))
    }
}
