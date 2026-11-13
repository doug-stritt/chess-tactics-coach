#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface StockfishBridge : NSObject
- (nullable instancetype)initWithNetworksAt:(NSString *)directory;
- (nullable NSDictionary<NSString *, id> *)analyzeFEN:(NSString *)fen
                                                moves:(NSArray<NSString *> *)moves
                                                nodes:(NSInteger)nodes;
@end

NS_ASSUME_NONNULL_END
