# Chess Tactics Coach · Gameplay build

Play standard chess offline as White against a local computer opponent. Drag a piece to a marked square, or tap the piece and then tap its destination. The game records moves in algebraic notation. **Undo turn** rolls back your move and the computer’s response, or just your move if the computer has yet to reply.

## Run on the iPhone simulator

1. Open `ChessTacticsCoach.xcodeproj` in Xcode.
2. Select the **ChessTacticsCoach** scheme and an iPhone simulator running iOS 17 or later.
3. Press **⌘R** to build and play. Press **⌘U** to run the rules and gameplay tests.

For a physical iPhone, select a development team under **Signing & Capabilities** and choose the phone as the run destination.

## Gameplay details

The app uses SwiftUI, a bundled copy of chess.js 1.4.0 running in JavaScriptCore for rules, and a lightweight local opponent with one difficulty. It treats threefold repetition and the fifty-move rule as automatic draws. Games are held in memory for the current session. The bundled rules library’s license is in `Coach/ChessJS-LICENSE.txt`.

## Piece artwork

The board and promotion picker use Lichess’s default Cburnett artwork by Colin M.L. Burnett. The original SVGs are bundled in the asset catalog. The attribution, upstream revision, and GPL version 2 or later license for the artwork are included in the project and app bundle.
