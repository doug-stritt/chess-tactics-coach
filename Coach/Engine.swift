import Foundation
import JavaScriptCore

struct Move: Codable, Hashable {
    let from: String
    let to: String
    let promotion: String?
    let san: String
}

struct Position: Decodable {
    let fen: String
    let moves: [Move]
    let ending: String?
    let inCheck: Bool

    var turn: String { fen.split(separator: " ")[1] == "w" ? "White" : "Black" }

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
    }

    struct Response: Decodable {
        var board: Position?
        var reply: Move?
        var error: String?
    }

    struct EngineError: LocalizedError {
        var errorDescription: String?
    }

    private var context: JSContext?

    func run(_ command: Command) throws -> Response {
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
