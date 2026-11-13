import SwiftUI

@MainActor
final class Game: ObservableObject {
    @Published private(set) var position: Position?
    @Published private(set) var moves: [Move] = []
    @Published private(set) var selected: String?
    @Published private(set) var busy = false
    @Published private(set) var thinking = false
    @Published private(set) var error: String?
    @Published private(set) var player = Side.white
    @Published var promotions: [Move] = []

    private let initialFEN: String?
    private let engine = ChessEngine()

    init(initialFEN: String? = nil) {
        self.initialFEN = initialFEN
    }

    private var generation = 0

    var destinations: Set<String> {
        Set(position?.moves.filter { $0.from == selected }.map(\.to) ?? [])
    }

    var canMove: Bool {
        position?.turn == player && position?.ending == nil && !busy && !thinking
    }

    private var openingPlies: Int { player == .black ? 1 : 0 }

    var canUndo: Bool { !busy && moves.count > openingPlies }

    func start(as side: Side = .white) {
        player = side
        promotions = []
        waitForBoard(history: [], computerReply: true)
    }

    func undo() {
        guard canUndo else { return }
        let played = moves.count - openingPlies
        let plies = played.isMultiple(of: 2) ? 2 : 1
        promotions = []
        waitForBoard(history: Array(moves.dropLast(plies)), computerReply: false)
    }

    func tap(_ square: String) {
        guard canMove, let position else { return }
        if let selected, move(from: selected, to: square) { return }
        selected = position.moves.contains { $0.from == square } && selected != square ? square : nil
    }

    @discardableResult
    func move(from source: String, to destination: String) -> Bool {
        guard canMove, let position else { return false }
        let legal = position.moves.filter { $0.from == source && $0.to == destination }
        if legal.count > 1 {
            promotions = legal
        } else if let move = legal.first {
            play(move)
        } else {
            return false
        }
        return true
    }

    func play(_ move: Move) {
        guard canMove, position?.moves.contains(move) == true else { return }
        promotions = []
        waitForBoard(history: moves + [move], computerReply: true)
    }

    func retryComputer() {
        guard !busy, !thinking, position?.turn == player.opposite, position?.ending == nil else { return }
        waitForBoard(history: moves, computerReply: true)
    }

    private func waitForBoard(history: [Move], computerReply: Bool) {
        generation += 1
        let revision = generation
        selected = nil
        error = nil
        busy = true
        thinking = false
        Task {
            do {
                let result = try await engine.run(.init(fen: initialFEN, moves: history)).board
                guard revision == generation else { return }
                position = result
                moves = history
                busy = false
                guard computerReply, result?.turn == player.opposite, result?.ending == nil else { return }
                thinking = true
                let reply = try await engine.run(.init(action: "reply", fen: initialFEN, moves: history))
                guard revision == generation else { return }
                guard let move = reply.reply else {
                    throw ChessEngine.EngineError(errorDescription: "The computer could not find a reply.")
                }
                let final = try await engine.run(.init(fen: initialFEN, moves: history, move: move)).board
                guard revision == generation else { return }
                moves = history + [move]
                position = final
                thinking = false
            } catch {
                guard revision == generation else { return }
                busy = false
                thinking = false
                self.error = error.localizedDescription
            }
        }
    }
}
