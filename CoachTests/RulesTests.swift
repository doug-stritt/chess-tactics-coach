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
