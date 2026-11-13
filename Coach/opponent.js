const RulesBoard = exports.Chess;
const values = { p: 100, n: 320, b: 330, r: 500, q: 900, k: 0 };

function board(fen) {
  return fen ? new RulesBoard(fen) : new RulesBoard();
}

function snapshot(position) {
  return {
    fen: position.fen(),
    inCheck: position.inCheck(),
    moves: position.moves({ verbose: true }).map(({ from, to, promotion, san }) => ({
      from, to, promotion, san
    })),
    ending: position.isCheckmate() ? 'Checkmate' :
      position.isStalemate() ? 'Stalemate' :
      position.isInsufficientMaterial() ? 'Draw · Insufficient material' :
      position.isThreefoldRepetition() ? 'Draw · Threefold repetition' :
      position.isDrawByFiftyMoves() ? 'Draw · Fifty-move rule' : null
  };
}

function evaluate(position) {
  let score = 0;
  for (const [rank, row] of position.board().entries()) {
    for (const [file, piece] of row.entries()) {
      if (!piece) continue;
      const center = 7 - Math.abs(rank - 3.5) - Math.abs(file - 3.5);
      const advance = piece.color === 'w' ? 6 - rank : rank - 1;
      let bonus = 0;
      if (piece.type === 'p') bonus = advance * 8 + center * 2;
      if (piece.type === 'n' || piece.type === 'b') bonus = center * 7;
      score += (values[piece.type] + bonus) * (piece.color === 'w' ? 1 : -1);
    }
  }
  return position.turn() === 'w' ? score : -score;
}

function priority(move) {
  return (move.captured ? 1000 + values[move.captured] * 10 - values[move.piece] : 0) +
    (move.promotion ? values[move.promotion] : 0) +
    (move.san.includes('+') || move.san.includes('#') ? 60 : 0);
}

function orderedMoves(position) {
  return position.moves({ verbose: true }).sort((a, b) => priority(b) - priority(a));
}

function search(position, depth, extensions, alpha, beta, ply) {
  const moves = orderedMoves(position);
  const inCheck = position.inCheck();
  if (!moves.length) return inCheck ? -30000 + ply : 0;
  if (position.isDraw()) return 0;
  let best = -Infinity;
  let candidates = moves;
  if (depth <= 0) {
    if (!inCheck || extensions <= 0) {
      best = evaluate(position);
      alpha = Math.max(alpha, best);
    }
    if (extensions <= 0 || alpha >= beta) return best;
    if (!inCheck) candidates = moves.filter(move => move.captured || move.promotion);
  }
  for (const move of candidates) {
    position.move(move);
    const score = -search(position, depth - 1, extensions - (depth <= 0 ? 1 : 0), -beta, -alpha, ply + 1);
    position.undo();
    best = Math.max(best, score);
    alpha = Math.max(alpha, score);
    if (alpha >= beta) break;
  }
  return best;
}

function computerMove(position) {
  if (position.isGameOver()) return null;
  const ranked = orderedMoves(position).map(move => {
    position.move(move);
    const score = -search(position, 1, 2, -Infinity, Infinity, 1);
    position.undo();
    return { move, score };
  }).sort((a, b) => b.score - a.score);

  const best = ranked[0];
  // Mate scores are near ±30000. Keep their exact ordering during forced lines.
  const margin = Math.abs(best.score) >= 29000 ? 0 : 24;
  const candidates = ranked.slice(0, 5).filter(candidate => best.score - candidate.score <= margin);
  const weights = candidates.map(candidate => margin + 1 - (best.score - candidate.score));
  let choice = Math.random() * weights.reduce((total, weight) => total + weight, 0);
  let selected = best;
  for (const [index, candidate] of candidates.entries()) {
    choice -= weights[index];
    if (choice < 0) {
      selected = candidate;
      break;
    }
  }

  const { from, to, promotion, san } = selected.move;
  return { from, to, promotion, san };
}

function runChess(command) {
  const { action, fen, moves, move } = JSON.parse(command);
  try {
    const position = board(fen);
    for (const previous of moves) position.move(previous);
    if (action === 'reply') return JSON.stringify({ reply: computerMove(position) });
    if (move) position.move(move);
    return JSON.stringify({ board: snapshot(position) });
  } catch (error) {
    return JSON.stringify({ error: error.message });
  }
}
