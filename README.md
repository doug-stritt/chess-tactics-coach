# Chess Tactics Coach · Gameplay build

Play standard chess offline against a local computer opponent. Choose **New game → Play as Black** to put Black at the bottom and let the computer open as White. Drag a piece to a marked square, or tap the piece and then tap its destination. The game records moves in algebraic notation. **Undo turn** rolls back your move and the computer’s response, or just your move if the computer has yet to reply. When you play Black, undo keeps the computer’s opening move.

## Run on the iPhone simulator

1. Open `ChessTacticsCoach.xcodeproj` in Xcode.
2. Select the **ChessTacticsCoach** scheme and an iPhone simulator running iOS 17 or later.
3. Press **⌘R** to build and play. Press **⌘U** to run the rules and gameplay tests.

For a physical iPhone, select a development team under **Signing & Capabilities** and choose the phone as the run destination.

## Gameplay details

The app uses SwiftUI, a bundled copy of chess.js 1.4.0 running in JavaScriptCore for rules, and a lightweight local opponent with one difficulty. The opponent mixes up its play by choosing among a small set of similarly rated moves, with a preference for higher scores. It treats threefold repetition and the fifty-move rule as automatic draws. Games are held in memory for the current session. The bundled rules library’s license is in `Coach/ChessJS-LICENSE.txt`.

## Piece artwork

The board and promotion picker use Lichess’s default Cburnett artwork by Colin M.L. Burnett. The original SVGs are bundled in the asset catalog. The attribution, upstream revision, and GPL version 2 or later license for the artwork are included in the project and app bundle.


## Tactic suggestions

On your turn, tap **Show tactic** to draw one line. Turn on **Auto-show tactics**
to reveal a suggestion automatically each time it is your turn. The numbered arrows show
up to two of your moves and the opponent’s intervening reply. Tap a tactic or **Best line** to show its arrows, moves, and expected score. Playing a move clears the
arrows. The search looks for checkmate or a net material gain after allowing
for an immediate recapture. When no tactic is found, the arrows show the engine’s highest-scoring move,
the predicted best reply, and your best follow-up if play continues.

The current and projected evaluations use pawn units from your side’s
perspective. The projection scores the board at the end of the displayed line.

Winning lines are labeled **Fork** when one piece threatens multiple pieces,
or **Discovered attack** when a move opens a bishop, rook, or queen attack.


## Stockfish analysis

Stockfish 18 evaluates the current position and the position at the end of
each displayed line. The best-line arrows come from Stockfish’s principal
variation. The local tactic detector still finds and labels motifs. Stockfish
checks candidate lines before they are shown. The playable computer opponent
keeps the existing varied move selection.

The first Xcode build downloads two pinned neural networks (about 113 MB)
from Stockfish’s network service, verifies their SHA-256 checksums, and bundles
them. The installed app analyzes positions offline. Xcode caches the downloads
in its build directory.

The bundled engine is built from the Stockfish source in `Stockfish/src`
at upstream revision `cb3d4ee9b47d0c5aae855b12379378ea1439675c` (tag
`sf_18`). The bridge and network build script are included in `Stockfish/`
along with Stockfish’s authors and GPLv3 license. See the
[upstream source](https://github.com/official-stockfish/Stockfish/tree/sf_18)
and [license terms](https://official-stockfish.github.io/docs/stockfish-wiki/Developers.html).


The [ChessFox tactics list](https://chessfox.com/chess-tactics-list/) informed
the motif labels. The coach also labels short tactical patterns in Stockfish’s
best line, including pins, skewers, double attacks, double checks, cross-checks,
clearance, deflection, sacrifices, underpromotion, and back-rank mate. Some
patterns need a longer line or endgame analysis to identify reliably.
