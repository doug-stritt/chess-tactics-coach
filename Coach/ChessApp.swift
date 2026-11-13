import SwiftUI

@main
struct ChessApp: App {
    var body: some Scene {
        WindowGroup { GameView(game: Game(initialFEN: initialFEN)) }
    }

    private var initialFEN: String? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--test-promotion") {
            return "4k3/P7/8/8/8/8/8/4K3 w - - 0 1"
        }
        #endif
        return nil
    }
}

struct GameView: View {
    @StateObject private var game: Game

    init(game: @autoclosure @escaping () -> Game) {
        _game = StateObject(wrappedValue: game())
    }
    @State private var chooseSide = false
    @GestureState private var drag: PieceDrag?

    private struct PieceDrag {
        let source: String
        let piece: Character
        let location: CGPoint
    }

    private let ink = Color(red: 0.15, green: 0.23, blue: 0.19)
    private let paper = Color(red: 0.97, green: 0.95, blue: 0.89)
    private let files = Array("abcdefgh")

    var body: some View {
        GeometryReader { geometry in
            let boardSize = min(geometry.size.width - 40, 472)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Chess")
                            .font(.system(size: 49, weight: .regular, design: .serif))
                            .accessibilityAddTraits(.isHeader)
                        Text("You play \(game.player.rawValue) · Computer plays \(game.player.opposite.rawValue)")
                            .font(.subheadline)
                            .foregroundStyle(ink.opacity(0.75))
                    }
                    status
                    board(size: boardSize)
                    HStack(spacing: 12) {
                        Button("Undo turn", systemImage: "arrow.uturn.backward") { game.undo() }
                            .disabled(!game.canUndo)
                        Spacer()
                        Button("New game", systemImage: "plus") {
                            chooseSide = true
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    moveList
                }
                .frame(width: boardSize)
                .padding(.top, 14)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(ink)
        .tint(ink)
        .background(paper.ignoresSafeArea())
        .task {
            if game.position == nil { game.start() }
        }
        .confirmationDialog("Choose your side", isPresented: $chooseSide, titleVisibility: .visible) {
            ForEach(Side.allCases, id: \.self) { side in
                Button("Play as \(side.rawValue)") { game.start(as: side) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choosing a side starts a new game.")
        }
        .sheet(isPresented: Binding(
            get: { !game.promotions.isEmpty },
            set: { if !$0 { game.promotions = [] } }
        )) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Promote pawn")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                ForEach(game.promotions, id: \.self) { move in
                    if let promotion = move.promotion.flatMap({ (game.player == .white ? $0.uppercased() : $0).first }) {
                        Button {
                            game.play(move)
                        } label: {
                            HStack(spacing: 12) {
                                pieceImage(promotion)
                                    .frame(width: 36, height: 44)
                                Text(pieceName(promotion))
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("promote-\(promotion.lowercased())")
                    }
                }
                Button("Cancel", role: .cancel) { game.promotions = [] }
                    .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(ink)
            .tint(ink)
            .presentationBackground(paper)
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                if game.busy || game.thinking {
                    ProgressView().controlSize(.small)
                } else {
                    Circle().fill(ink).frame(width: 7, height: 7).accessibilityHidden(true)
                }
                Text(statusText)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("game-status")
            }
            if let error = game.error {
                Text(error).font(.footnote)
                if game.position?.turn == game.player.opposite && game.position?.ending == nil {
                    Button("Retry computer move") { game.retryComputer() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(ink.opacity(0.075), in: RoundedRectangle(cornerRadius: 10))
    }

    private var statusText: String {
        if let position = game.position, let ending = position.ending {
            if ending == "Checkmate" {
                return position.turn == game.player.opposite ? "Checkmate · You win" : "Checkmate · Computer wins"
            }
            return ending
        }
        if game.thinking { return "Computer is thinking…" }
        if game.busy || game.position == nil { return "Setting the board…" }
        if game.position?.turn == game.player.opposite { return "Computer to move" }
        return game.position?.inCheck == true ? "Your move · Check" : "Your move"
    }

    private func board(size: CGFloat) -> some View {
        let squareSize = size / 8
        let pieces = game.position?.pieces ?? [:]
        let legalMoves = game.position?.moves ?? []
        let movable = game.canMove ? Set(legalMoves.map(\.from)) : []
        let activeDrag = game.canMove ? drag : nil
        let destinations = activeDrag.map { drag in
            Set(legalMoves.filter { $0.from == drag.source }.map(\.to))
        } ?? game.destinations
        return VStack(spacing: 0) {
            ForEach(0..<8) { row in
                HStack(spacing: 0) {
                    ForEach(0..<8) { col in
                        let square = boardSquare(row: row, column: col)
                        squareView(square, piece: pieces[square], size: squareSize, row: row, col: col,
                                   destination: destinations.contains(square),
                                   selected: (activeDrag?.source ?? game.selected) == square,
                                   lifted: activeDrag?.source == square)
                            .highPriorityGesture(pieceDrag(from: square, piece: pieces[square], size: size),
                                                 including: movable.contains(square) ? .gesture : .none)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(ink.opacity(0.15)))
        .overlay(alignment: .topLeading) {
            if let activeDrag {
                pieceImage(activeDrag.piece)
                    .frame(width: squareSize, height: squareSize)
                    .shadow(radius: 3, y: 2)
                    .position(activeDrag.location)
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: "chessboard")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chessboard")
    }

    private func pieceDrag(from source: String, piece: Character?, size: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("chessboard"))
            .updating($drag) { value, state, _ in
                if let piece, game.canMove {
                    state = PieceDrag(source: source, piece: piece, location: value.location)
                }
            }
            .onEnded { value in
                let point = value.location
                guard point.x >= 0, point.y >= 0, point.x < size, point.y < size else { return }
                let squareSize = size / 8
                let column = Int(point.x / squareSize)
                let row = Int(point.y / squareSize)
                game.move(from: source, to: boardSquare(row: row, column: column))
            }
    }

    private func boardSquare(row: Int, column: Int) -> String {
        let flipped = game.player == .black
        return "\(files[flipped ? 7 - column : column])\(flipped ? row + 1 : 8 - row)"
    }

    private func squareView(_ square: String, piece: Character?, size: CGFloat, row: Int, col: Int,
                            destination: Bool, selected: Bool, lifted: Bool) -> some View {
        let dark = (row + col).isMultiple(of: 2) == false
        let latest = game.moves.last
        let highlighted = latest?.from == square || latest?.to == square
        let background = dark ? Color(red: 0.40, green: 0.53, blue: 0.41) :
            Color(red: 0.91, green: 0.87, blue: 0.72)
        return Button {
            game.tap(square)
        } label: {
            ZStack {
                Rectangle().fill(background)
                if highlighted || selected {
                    Rectangle().fill(Color(red: 0.99, green: 0.74, blue: 0.29).opacity(selected ? 0.78 : 0.45))
                }
                if destination {
                    Circle()
                        .strokeBorder(ink.opacity(0.52), lineWidth: piece == nil ? 0 : 3)
                        .background(ink.opacity(piece == nil ? 0.35 : 0), in: Circle())
                        .frame(width: size * (piece == nil ? 0.25 : 0.93))
                }
                if let piece {
                    pieceImage(piece)
                        .frame(width: size, height: size)
                        .opacity(lifted ? 0 : 1)
                }
                if col == 0 {
                    Text(String(square.suffix(1))).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(3).font(.system(size: 8, weight: .bold))
                }
                if row == 7 {
                    Text(String(square.prefix(1))).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(3).font(.system(size: 8, weight: .bold))
                }
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!game.canMove)
        .accessibilityIdentifier("square-\(square)")
        .accessibilityLabel(piece.map { "\(square), \($0.isUppercase ? "white" : "black") \(pieceName($0))" } ?? square)
        .accessibilityValue(selected ? "Selected" : destination ? "Legal destination" : "")
    }

    private var moveList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Moves")
                .font(.system(.title3, design: .serif).weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            if game.moves.isEmpty {
                Text("Drag a piece or tap it, then tap a marked square.")
                    .font(.footnote)
            } else {
                let rows = stride(from: 0, to: game.moves.count, by: 2).map { index in
                    let white = game.moves[index].san
                    let black = game.moves.indices.contains(index + 1) ? " \(game.moves[index + 1].san)" : ""
                    return "\(index / 2 + 1). \(white)\(black)"
                }
                Text(rows.joined(separator: "   "))
                    .font(.system(.footnote, design: .monospaced))
                    .accessibilityIdentifier("move-list")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pieceImage(_ piece: Character) -> some View {
        let color = piece.isUppercase ? "w" : "b"
        return Image(decorative: color + piece.uppercased())
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }

    private func pieceName(_ piece: Character?) -> String {
        let names = ["k": "King", "q": "Queen", "r": "Rook", "b": "Bishop", "n": "Knight", "p": "Pawn"]
        return piece.flatMap { names[$0.lowercased()] } ?? "Piece"
    }
}
