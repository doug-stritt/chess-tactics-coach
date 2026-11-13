const RulesBoard = exports.Chess;
const values = { p: 100, n: 320, b: 330, r: 500, q: 900, k: 0 };

function board(fen) {
  return fen ? new RulesBoard(fen) : new RulesBoard();
}

function snapshot(position) {
  return {
    fen: position.fen(),
    inCheck: position.inCheck(),
    evaluation: whiteEvaluation(position),
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

// Keep both displayed scores on the same scale, from White’s perspective.
function whiteEvaluation(position) {
  const sign = position.turn() === 'w' ? 1 : -1;
  if (position.isCheckmate()) return -30000 * sign;
  if (position.isDraw()) return 0;
  return evaluate(position) * sign;
}

function scoredLine(position, line, labelTactics = false) {
  const motifs = new Set();
  const played = [];
  for (const [index, move] of line.entries()) {
    if (labelTactics && index % 2 === 0) {
      for (const motif of playAndIdentifyMotifs(position, move, played)) motifs.add(motif);
    } else {
      position.move(move);
    }
    played.push(move);
  }
  const evaluation = whiteEvaluation(position);
  for (const _ of line) position.undo();
  return { moves: line.map(moveData), evaluation, motifs: [...motifs] };
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

function rankMoves(position) {
  return orderedMoves(position).map(move => {
    position.move(move);
    const score = -search(position, 1, 2, -Infinity, Infinity, 1);
    position.undo();
    return { move, score };
  }).sort((a, b) => b.score - a.score);
}

function computerMove(position) {
  if (position.isGameOver()) return null;
  const ranked = rankMoves(position);
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

function moveData({ from, to, promotion, san }) {
  return { from, to, promotion, san };
}

function materialGain(move) {
  return (values[move.captured] ?? 0) +
    (move.promotion ? values[move.promotion] - values.p : 0);
}

function isBetween(square, start, end) {
  const coordinates = name => [name.charCodeAt(0), Number(name[1])];
  const [x, y] = coordinates(square);
  const [sx, sy] = coordinates(start);
  const [ex, ey] = coordinates(end);
  return (x - sx) * (ey - sy) === (y - sy) * (ex - sx) &&
    (x - sx) * (ex - x) + (y - sy) * (ey - y) > 0;
}

// Treat a geometric attack as a threat when it checks the king, attacks a
// more valuable piece, or attacks an undefended piece.
function playAndIdentifyMotifs(position, move, played) {
  const friendly = position.turn();
  const enemy = friendly === 'w' ? 'b' : 'w';
  const targets = position.board().flat().filter(piece =>
    piece && piece.color === enemy && piece.type !== 'p' && piece.square !== move.to
  ).map(piece => ({ ...piece, before: position.attackers(piece.square, friendly) }));

  const wasInCheck = position.inCheck();
  const captured = position.get(move.to);
  const attackedMover = position.attackers(move.from, enemy).length > 0;
  const removedDefense = captured && targets.some(target =>
    position.attackers(target.square, enemy).includes(move.to) &&
    position.attackers(target.square, friendly).length > 0
  );
  const followUpDefenders = captured
    ? position.attackers(move.to, enemy) : [];
  position.move(move);
  const moved = position.get(move.to);
  let forkTargets = 0;
  let hasNewForkAttack = false;
  let discovered = false;
  const newThreats = new Map();
  for (const target of targets) {
    const defenders = position.attackers(target.square, enemy);
    const isThreat = attacker => target.type === 'k' ||
      values[target.type] > values[attacker.type] || defenders.length === 0;
    const attackers = position.attackers(target.square, friendly);
    for (const square of attackers) {
      if (!target.before.includes(square === move.to ? move.from : square) &&
          isThreat(position.get(square))) {
        if (!newThreats.has(square)) newThreats.set(square, new Set());
        newThreats.get(square).add(target.square);
      }
    }
    if (attackers.includes(move.to) && isThreat(moved)) {
      forkTargets += 1;
      if (!target.before.includes(move.from)) hasNewForkAttack = true;
    }
    if (attackers.some(square => {
      if (square === move.to || target.before.includes(square) ||
          !isBetween(move.from, square, target.square)) return false;
      const slider = position.get(square);
      return ['b', 'r', 'q'].includes(slider.type) && isThreat(slider);
    })) discovered = true;
  }
  const motifs = [];
  if (forkTargets >= 2 && hasNewForkAttack) motifs.push('Fork');
  if (discovered) motifs.push('Discovered attack');
  const distinctTargets = new Set([...newThreats.values()].flatMap(squares => [...squares]));
  if (newThreats.size > 1 && distinctTargets.size > 1 && forkTargets < 2) motifs.push('Double attack');
  const king = targets.find(piece => piece.type === 'k');
  const checks = king ? position.attackers(king.square, friendly) : [];
  if (checks.length >= 2) motifs.push('Double check');
  if (wasInCheck && checks.length && moved.type !== 'k' && !move.captured) motifs.push('Cross-check');

  const previous = played.at(-1);
  const setup = played.at(-2);
  if (setup && previous) {
    if (move.to === setup.from && move.from !== setup.to && (checks.length || move.captured)) {
      motifs.push('Clearance');
    }
    if (previous.to === setup.to && previous.captured && captured && move.to !== previous.to &&
        !followUpDefenders.includes(previous.to)) {
      // Check whether the recapturing piece defended this target before it moved.
      position.undo();
      position.undo();
      const defended = position.attackers(move.to, enemy).includes(previous.from);
      position.move(previous);
      position.move(move);
      if (defended) motifs.push('Deflection');
    }
    if (previous.to === setup.to && previous.captured && captured &&
        values[previous.captured] > (values[setup.captured] ?? 0)) motifs.push('Sacrifice');
  }
  if (removedDefense && distinctTargets.size > 0) motifs.push('Remove the defender');
  if (attackedMover && captured && !position.isAttacked(move.to, enemy)) motifs.push('Hit-and-run');
  if (moved.type === 'r' && move.to[1] === (friendly === 'w' ? '7' : '2') &&
      move.from[1] !== move.to[1] &&
      position.board().flat().some(piece => piece?.type === 'r' && piece.color === friendly &&
        piece.square !== move.to && piece.square[1] === move.to[1])) motifs.push('Two rooks on the seventh rank');
  if (move.promotion && move.promotion !== 'q') motifs.push('Underpromotion');
  if (position.isStalemate()) motifs.push('Stalemate');
  if (position.isCheckmate()) {
    motifs.push('Checkmate');
    const backRank = enemy === 'b' ? '8' : '1';
    if (king.square[1] === backRank && move.to[1] === backRank &&
        ['r', 'q'].includes(moved.type) && checks.includes(move.to)) {
      const shieldRank = enemy === 'b' ? 7 : 2;
      const shield = position.board().flat().filter(piece =>
        piece?.color === enemy && piece.type === 'p' && Number(piece.square[1]) === shieldRank &&
        Math.abs(piece.square.charCodeAt(0) - king.square.charCodeAt(0)) <= 1);
      if (shield.length >= 2) motifs.push('Back-rank mate');
    }
  }
  identifyRayMotifs(position, move, targets, motifs);
  return motifs;
}

function identifyRayMotifs(position, move, targets, motifs) {
  const piece = position.get(move.to);
  if (!['b', 'r', 'q'].includes(piece.type)) return;
  for (const front of targets) {
    if (!position.attackers(front.square, piece.color).includes(move.to) ||
        front.before.includes(move.from)) continue;
    for (const rear of targets) {
      if (!isBetween(front.square, move.to, rear.square)) continue;
      const dx = Math.sign(rear.square.charCodeAt(0) - front.square.charCodeAt(0));
      const dy = Math.sign(Number(rear.square[1]) - Number(front.square[1]));
      let file = front.square.charCodeAt(0) + dx;
      let rank = Number(front.square[1]) + dy;
      while (file !== rear.square.charCodeAt(0) || rank !== Number(rear.square[1])) {
        if (position.get(String.fromCharCode(file) + rank)) break;
        file += dx;
        rank += dy;
      }
      if (file !== rear.square.charCodeAt(0) || rank !== Number(rear.square[1])) continue;
      if (front.type === 'k') motifs.push('Skewer');
      else if (rear.type === 'k') motifs.push('Pin');
      else if (values[front.type] > values[rear.type]) motifs.push('Skewer');
      else if (values[rear.type] > values[front.type]) motifs.push('Pin');
    }
  }
}

// A line must work against every legal reply. Show the reply that leaves
// the smallest gain, and account for one immediate recapture.
function tactics(position) {
  const suggestions = [];
  for (const first of position.moves({ verbose: true })) {
    if (first.san.endsWith('#')) {
      suggestions.push({ score: 30000, line: [first] });
      continue;
    }
    position.move(first);
    const replies = position.isDraw() ? [] : position.moves({ verbose: true });
    let weakest;
    for (const reply of replies) {
      position.move(reply);
      let best;
      if (!position.isGameOver()) {
        for (const follow of position.moves({ verbose: true })) {
          const gain = materialGain(first) - materialGain(reply) + materialGain(follow);
          const mate = follow.san.endsWith('#');
          if (!mate && (!(first.captured || follow.captured) || gain <= (best?.score ?? 0))) continue;
          let score = mate ? 30000 : gain;
          if (!mate) {
            position.move(follow);
            const recapture = Math.max(0, ...position.moves({ verbose: true }).map(materialGain));
            score = position.isDraw() ? 0 : gain - recapture;
            position.undo();
          }
          if (score > (best?.score ?? 0)) best = { score, line: [first, reply, follow] };
        }
      }
      position.undo();
      if (!best) {
        weakest = undefined;
        break;
      }
      if (!weakest || best.score < weakest.score) weakest = best;
    }
    position.undo();
    if (weakest) suggestions.push(weakest);
  }
  return suggestions.sort((a, b) => b.score - a.score).map(({ line }) => line);
}

function runChess(command) {
  const { action, fen, moves, move, line } = JSON.parse(command);
  try {
    const position = board(fen);
    for (const previous of moves) position.move(previous);
    if (action === 'tactics') {
      if (position.isGameOver()) return JSON.stringify({ tactics: [] });
      return JSON.stringify({ tactics: tactics(position).map(moves => scoredLine(position, moves, true)) });
    }
    if (action === 'line') {
      const converted = [];
      for (const uci of line) {
        if (position.isGameOver()) break;
        converted.push(position.move({ from: uci.slice(0, 2), to: uci.slice(2, 4), promotion: uci[4] }));
      }
      for (const _ of converted) position.undo();
      return JSON.stringify({ bestLine: scoredLine(position, converted, true) });
    }
    if (action === 'reply') return JSON.stringify({ reply: computerMove(position) });
    if (move) position.move(move);
    return JSON.stringify({ board: snapshot(position) });
  } catch (error) {
    return JSON.stringify({ error: error.message });
  }
}
