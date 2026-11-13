import Foundation
import JavaScriptCore

struct Move: Codable, Hashable {
    let from: String
    let to: String
    let promotion: String?
    let san: String

    var uci: String { from + to + (promotion ?? "") }
}

enum Side: String, CaseIterable {
    case white = "White"
    case black = "Black"

    var opposite: Side { self == .white ? .black : .white }
}

struct SuggestedLine: Codable, Equatable {
    let moves: [Move]
    let evaluation: Int
    let motifs: [String]
}

struct Position: Decodable {
    var evaluation: Int
    let fen: String
    let moves: [Move]
    let ending: String?
    let inCheck: Bool

    var turn: Side { fen.split(separator: " ")[1] == "w" ? .white : .black }

    var pieces: [String: Character] {
        var result: [String: Character] = [:]
        for (row, rank) in fen.split(separator: " ")[0].split(separator: "/").enumerated() {
            var file = 0
            for character in rank {
                if let empty = character.wholeNumberValue {
                    file += empty
                } else {
                    result["\(Array("abcdefgh")[file])\(8 - row)"] = character
                    file += 1
                }
            }
        }
        return result
    }
}

actor ChessEngine {
    struct Command: Encodable {
        var action = "board"
        var fen: String? = nil
        var moves: [Move] = []
        var move: Move? = nil
        var line: [String]? = nil
    }

    struct Response: Decodable {
        var board: Position?
        var reply: Move?
        var tactics: [SuggestedLine]?
        var bestLine: SuggestedLine?
        var error: String?
    }

    struct EngineError: LocalizedError {
        var errorDescription: String?
    }

    private var context: JSContext?
    private var stockfish: StockfishBridge?

    private static let startingFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    private static let searchNodes = 20_000

    func run(_ command: Command) throws -> Response {
        var response = try rules(command)
        if command.action == "board", var position = response.board, position.ending == nil {
            let history = command.moves + [command.move].compactMap { $0 }
            position.evaluation = try analyze(fen: command.fen, history: history, turn: position.turn).score
            response.board = position
        } else if command.action == "tactics" {
            let position = try board(fen: command.fen, history: command.moves)
            guard position.ending == nil else { return response }
            let analysis = try analyze(fen: command.fen, history: command.moves, turn: position.turn)
            let perspective = position.turn == .white ? 1 : -1
            var scored: [SuggestedLine] = []
            for candidate in (response.tactics ?? []).prefix(8) {
                let line = try scoreLine(candidate, fen: command.fen, history: command.moves)
                // Keep tactics reasonably close to Stockfish's best line.
                if perspective * line.evaluation >= perspective * analysis.score - 100 {
                    scored.append(line)
                }
            }
            let converted = try rules(.init(action: "line", fen: command.fen, moves: command.moves,
                                            line: Array(analysis.pv.prefix(3))))
            if let line = converted.bestLine {
                let best = try scoreLine(line, fen: command.fen, history: command.moves)
                response.bestLine = best
                if !best.motifs.isEmpty && !scored.contains(where: { $0.moves.first == best.moves.first }) {
                    scored.insert(best, at: 0)
                }
            }
            response.tactics = scored.sorted {
                if $0.motifs.isEmpty != $1.motifs.isEmpty { return !$0.motifs.isEmpty }
                return perspective * $0.evaluation > perspective * $1.evaluation
            }
        }
        return response
    }

    private func board(fen: String?, history: [Move]) throws -> Position {
        guard let result = try rules(.init(fen: fen, moves: history)).board else {
            throw EngineError(errorDescription: "The chess position could not be loaded.")
        }
        return result
    }

    private func scoreLine(_ line: SuggestedLine, fen: String?, history: [Move]) throws -> SuggestedLine {
        let updated = history + line.moves
        let endpoint = try board(fen: fen, history: updated)
        let score = endpoint.ending == nil
            ? try analyze(fen: fen, history: updated, turn: endpoint.turn).score
            : endpoint.evaluation
        return SuggestedLine(moves: line.moves, evaluation: score, motifs: line.motifs)
    }

    private func analyze(fen: String?, history: [Move], turn: Side) throws -> (score: Int, pv: [String]) {
        if stockfish == nil, let path = Bundle.main.resourcePath {
            stockfish = StockfishBridge(networksAt: path)
        }
        guard let result = stockfish?.analyzeFEN(fen ?? Self.startingFEN,
                                                  moves: history.map(\.uci), nodes: Self.searchNodes),
              let score = result["score"] as? Int, let pv = result["pv"] as? [String] else {
            throw EngineError(errorDescription: "Stockfish analysis is unavailable.")
        }
        return (turn == .white ? score : -score, pv)
    }

    private func rules(_ command: Command) throws -> Response {
        if context == nil {
            guard let fresh = JSContext() else { throw EngineError(errorDescription: "Chess engine failed to start.") }
            fresh.evaluateScript("var exports = {};")
            for name in ["chess", "opponent"] {
                guard let url = Bundle.main.url(forResource: name, withExtension: "js") else {
                    throw EngineError(errorDescription: "Missing chess engine resource.")
                }
                fresh.evaluateScript(try String(contentsOf: url, encoding: .utf8))
                if let exception = fresh.exception {
                    throw EngineError(errorDescription: exception.toString())
                }
            }
            context = fresh
        }
        let data = try JSONEncoder().encode(command)
        guard let result = context?.objectForKeyedSubscript("runChess")?
            .call(withArguments: [String(decoding: data, as: UTF8.self)])?.toString() else {
            throw EngineError(errorDescription: "Chess engine returned no result.")
        }
        let response = try JSONDecoder().decode(Response.self, from: Data(result.utf8))
        if let error = response.error { throw EngineError(errorDescription: error) }
        return response
    }
}
