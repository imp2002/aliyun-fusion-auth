#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Internal adapter for the exact vendor binary shipped in the 1.2.15 archive.
// This is deliberately not part of the Flutter or CocoaPods public interface.
@interface AFSDKCleanup : NSObject
+ (BOOL)isSupported;
- (nullable instancetype)initWithHandler:(id)handler;
- (void)destroyWithCompletion:(dispatch_block_t)completion;
@end

NS_ASSUME_NONNULL_END
