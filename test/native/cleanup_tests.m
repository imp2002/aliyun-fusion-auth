#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "../../ios/Classes/AFSDKCleanup.h"

static NSString *version = @"1.2.14";
static NSUInteger checks;
static void Check(BOOL condition, NSString *message) {
  checks++;
  if (!condition) {
    NSLog(@"FAIL: %@", message);
    exit(1);
  }
}

@interface AlicomFusionNumberAuthBusiness : NSObject
@property (nonatomic) BOOL isPresentedLoginVC;
@property (nonatomic) NSUInteger realCancels;
@property (nonatomic, strong) NSMutableArray *callbacks;
- (void)cancelLoginVCAnimated:(BOOL)animated request:(id)request complete:(void (^)(id))complete;
@end
@implementation AlicomFusionNumberAuthBusiness
- (instancetype)init {
  if ((self = [super init]))
    _callbacks = [NSMutableArray array];
  return self;
}
- (void)cancelLoginVCAnimated:(BOOL)animated request:(id)request complete:(void (^)(id))complete {
  Check(NSThread.isMainThread, @"Actual SDK cancellation runs on main");
  if (!self.isPresentedLoginVC)
    return;
  self.realCancels++;
  __weak AlicomFusionNumberAuthBusiness *weakSelf = self;
  [self.callbacks addObject:[^(id response) {
                    weakSelf.isPresentedLoginVC = NO;
                    if (complete)
                      complete(response);
                  } copy]];
}
@end
@interface AlicomFusionThreadService : NSObject
@property (nonatomic, strong) AlicomFusionNumberAuthBusiness *numberAuthBusiness;
@end
@implementation AlicomFusionThreadService
- (instancetype)init {
  if ((self = [super init]))
    _numberAuthBusiness = [AlicomFusionNumberAuthBusiness new];
  return self;
}
@end
@interface AlicomFusionTimerService : NSObject
@property (nonatomic, strong) AlicomFusionThreadService *threadService;
@end
@implementation AlicomFusionTimerService
- (instancetype)init {
  if ((self = [super init]))
    _threadService = [AlicomFusionThreadService new];
  return self;
}
@end
@interface AlicomFusionBusiness : NSObject
@property (nonatomic, strong) dispatch_queue_t inputQueue;
@property (nonatomic, strong) AlicomFusionTimerService *timerService;
@property (nonatomic) NSUInteger requestCount;
@property (nonatomic) NSUInteger tails;
@property (nonatomic) BOOL graphTail;
@property (nonatomic, copy) dispatch_block_t scheduled;
- (void)destroy;
@end
@implementation AlicomFusionBusiness
- (instancetype)init {
  if ((self = [super init])) {
    _inputQueue = dispatch_queue_create("cleanup.fake.vendor.input", DISPATCH_QUEUE_SERIAL);
    _timerService = [AlicomFusionTimerService new];
  }
  return self;
}
- (void)destroy {
  dispatch_async(self.inputQueue, ^{
    for (NSUInteger i = 0; i < self.requestCount; i++) {
      [self.timerService.threadService.numberAuthBusiness cancelLoginVCAnimated:YES
                                                                        request:nil
                                                                       complete:^(id response) {
                                                                         self.tails++;
                                                                       }];
    }
    // Graph's callback is a main block queued from inside vendor destroy.
    dispatch_async(dispatch_get_main_queue(), ^{
      self.graphTail = YES;
    });
    dispatch_async(dispatch_get_main_queue(), self.scheduled);
  });
}
@end
@interface AlicomFusionAuthHandler : NSObject
@property (nonatomic, strong) AlicomFusionBusiness *business;
+ (NSString *)getSDKVersion;
- (void)destroy;
@end
@implementation AlicomFusionAuthHandler
+ (NSString *)getSDKVersion {
  return version;
}
- (instancetype)init {
  if ((self = [super init]))
    _business = [AlicomFusionBusiness new];
  return self;
}
- (void)destroy {
  [self.business destroy];
  self.business = nil;
}
@end

static void RunCase(NSUInteger requests, BOOL shown, dispatch_block_t next) {
  AlicomFusionAuthHandler *handler = [AlicomFusionAuthHandler new];
  AlicomFusionBusiness *business = handler.business;
  AlicomFusionNumberAuthBusiness *number = business.timerService.threadService.numberAuthBusiness;
  number.isPresentedLoginVC = shown;
  business.requestCount = requests;
  Class originalClass = object_getClass(number);
  AFSDKCleanup *cleanup = [[AFSDKCleanup alloc] initWithHandler:handler];
  Check(cleanup != nil, @"Supported object graph attaches");
  Check(object_getClass(number) != originalClass, @"Only current instance changes class");
  Check(object_getClass([AlicomFusionNumberAuthBusiness new]) == originalClass,
        @"Other SDK instances unchanged");
  __block NSUInteger completed = 0;
  business.scheduled = ^{
    Check(completed == 0, @"Input barrier cannot complete before pending main UI work");
    Check(number.realCancels == (shown && requests ? 1 : 0), @"Duplicate cancellations serialize");
    if (shown && requests) {
      void (^callback)(id) = number.callbacks.firstObject;
      // Keep it pending for another queue turn; no timer or sleep constitutes proof.
      dispatch_async(dispatch_get_main_queue(), ^{
        Check(completed == 0, @"Late carrier completion keeps cleanup pending");
        callback(nil);
        Check(business.tails == 1, @"Vendor cleanup tail runs before group completes");
        callback(nil);
        Check(business.tails == 1, @"Duplicate vendor callback is ignored");
      });
    }
  };
  [cleanup destroyWithCompletion:^{
    completed++;
    Check(completed == 1, @"Cleanup completes once");
    Check(business.graphTail, @"Main graph cleanup tail precedes completion");
    Check(object_getClass(number) == originalClass, @"Instance class restored after teardown");
    Check(number.realCancels == (shown && requests ? 1 : 0), @"Only one UIKit dismissal needed");
    for (void (^callback)(id) in number.callbacks)
      callback(nil);
    Check(business.tails == (shown && requests ? 1 : 0),
          @"Late duplicate cannot clear next SDK state");
    [cleanup destroyWithCompletion:^{
      Check(NO, @"Repeated destroy must not complete twice");
    }];
    business.scheduled = nil;
    [number.callbacks removeAllObjects];
    dispatch_async(dispatch_get_main_queue(), next);
  }];
  [cleanup destroyWithCompletion:^{
    Check(NO, @"Concurrent repeated destroy must be ignored");
  }];
}

int main(void) {
  @autoreleasepool {
    Check([AFSDKCleanup isSupported], @"Pinned vendor ABI supported");
    version = @"9.9.9";
    Check(![AFSDKCleanup isSupported], @"Different SDK rejected before construction");
    version = @"1.2.14";
    dispatch_async(dispatch_get_main_queue(), ^{
      RunCase(0, NO, ^{
        RunCase(2, NO, ^{
          RunCase(1, YES, ^{
            RunCase(2, YES, ^{
              NSLog(@"PASS: %lu cleanup assertions (no UI / one cancel / two cancels / main "
                    @"ordering / late & duplicate callbacks)",
                    (unsigned long)checks);
              exit(0);
            });
          });
        });
      });
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(),
                   ^{
                     NSLog(@"FAIL: cleanup test did not complete");
                     exit(2);
                   });
    CFRunLoopRun();
  }
}
