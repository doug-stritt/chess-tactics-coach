#import "StockfishBridge.h"
#include "src/bitboard.h"
#include "src/engine.h"
#include "src/evaluate.h"
#include "src/position.h"
#include "src/uci.h"

#include <memory>
#include <mutex>
#include <sstream>

@implementation StockfishBridge {
    std::unique_ptr<Stockfish::Engine> _engine;
}

- (instancetype)initWithNetworksAt:(NSString *)directory {
    self = [super init];
    if (!self) return nil;
    for (NSString *name in @[@(EvalFileDefaultNameBig), @(EvalFileDefaultNameSmall)]) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:[directory stringByAppendingPathComponent:name]]) {
            return nil;
        }
    }
    static std::once_flag initialize;
    std::call_once(initialize, [] {
        Stockfish::Bitboards::init();
        Stockfish::Position::init();
    });
    _engine = std::make_unique<Stockfish::Engine>(
        std::string([directory stringByAppendingPathComponent:@"stockfish"].UTF8String));
    _engine->set_on_verify_networks([](std::string_view) {});
    _engine->set_on_bestmove([](std::string_view, std::string_view) {});
    _engine->set_on_iter([](const auto&) {});
    _engine->set_on_update_no_moves([](const auto&) {});
    return self;
}

- (NSDictionary<NSString *, id> *)analyzeFEN:(NSString *)fen
                                      moves:(NSArray<NSString *> *)moves
                                      nodes:(NSInteger)nodes {
    std::vector<std::string> history;
    for (NSString *move in moves) history.emplace_back(move.UTF8String);
    int score = 0;
    bool found = false;
    std::string pv;
    _engine->set_on_update_full([&](const Stockfish::Engine::InfoFull& info) {
        if (!info.bound.empty()) return;
        const auto text = Stockfish::UCIEngine::format_score(info.score);
        if (text.starts_with("mate ")) {
            score = std::stoi(text.substr(5)) > 0 ? 30000 : -30000;
        } else {
            score = std::stoi(text.substr(3));
        }
        pv = info.pv;
        found = true;
    });
    _engine->set_position(fen.UTF8String, history);
    Stockfish::Search::LimitsType limits;
    limits.nodes = nodes;
    limits.startTime = Stockfish::now();
    _engine->go(limits);
    _engine->wait_for_search_finished();
    _engine->set_on_update_full([](const auto&) {});
    if (!found) return nil;

    NSMutableArray<NSString *> *line = [NSMutableArray array];
    std::istringstream stream(pv);
    std::string move;
    while (stream >> move) [line addObject:@(move.c_str())];
    return @{@"score": @(score), @"pv": line};
}
@end
