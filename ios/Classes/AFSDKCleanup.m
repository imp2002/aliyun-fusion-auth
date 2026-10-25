#import "AFSDKCleanup.h"
#import <objc/message.h>
#import <objc/runtime.h>

static char AFTrackerKey;
static Class AFTrackedNumberClass;
typedef void (*AFCancelImplementation)(id, SEL, BOOL, id, void (^)(id));

static BOOL AFMethodMatches(Class cls, NSString *name, const char *result,
                            NSArray<NSString *> *arguments) {
  Method method = class_getInstanceMethod(cls, NSSelectorFromString(name));
  if (!method)
    return NO;
  NSMethodSignature *signature =
      [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
  if (strcmp(signature.methodReturnType, result) ||
      signature.numberOfArguments != arguments.count + 2)
    return NO;
  for (NSUInteger index = 0; index < arguments.count; index++) {
    if (strcmp([signature getArgumentTypeAtIndex:index + 2], arguments[index].UTF8String))
      return NO;
  }
  return YES;
}

static id AFObject(id object, NSString *selector) {
  return ((id (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(selector));
}

@interface AFSDKCleanup ()
@property (nonatomic, strong) id handler;
@property (nonatomic, strong) id business;
@property (nonatomic, weak) id numberBusiness;
@property (nonatomic, strong) dispatch_queue_t inputQueue;
@property (nonatomic, strong) dispatch_group_t cancellations;
@property (nonatomic, assign) AFCancelImplementation originalCancel;
@property (nonatomic, assign) BOOL destroying;
@property (nonatomic, strong) NSMutableArray<dispatch_block_t> *queuedCancellations;
@property (nonatomic, assign) BOOL cancelling;
- (void)cancelNumberBusiness:(id)number
                    selector:(SEL)selector
                    animated:(BOOL)animated
                     request:(id)request
                  completion:(void (^)(id))completion;
- (void)drainCancellations;
@end

static void AFTrackedCancel(id number, SEL selector, BOOL animated, id request,
                            void (^completion)(id)) {
  AFSDKCleanup *tracker = objc_getAssociatedObject(number, &AFTrackerKey);
  [tracker cancelNumberBusiness:number
                       selector:selector
                       animated:animated
                        request:request
                     completion:completion];
}

@implementation AFSDKCleanup

+ (BOOL)isSupported {
  // The supplied archive is named 1.2.15, but both its binaries report 1.2.14.
  // Do not widen this check for a vendor upgrade without auditing its teardown.
  Class handler = NSClassFromString(@"AlicomFusionAuthHandler");
  Class business = NSClassFromString(@"AlicomFusionBusiness");
  Class timer = NSClassFromString(@"AlicomFusionTimerService");
  Class thread = NSClassFromString(@"AlicomFusionThreadService");
  Class number = NSClassFromString(@"AlicomFusionNumberAuthBusiness");
  if (!handler || !business || !timer || !thread || !number ||
      !AFMethodMatches(object_getClass(handler), @"getSDKVersion", @encode(id), @[]) ||
      ![AFObject(handler, @"getSDKVersion") isEqual:@"1.2.14"] ||
      !AFMethodMatches(handler, @"business", @encode(id), @[]) ||
      !AFMethodMatches(handler, @"destroy", @encode(void), @[]) ||
      !AFMethodMatches(business, @"inputQueue", @encode(id), @[]) ||
      !AFMethodMatches(business, @"timerService", @encode(id), @[]) ||
      !AFMethodMatches(timer, @"threadService", @encode(id), @[]) ||
      !AFMethodMatches(thread, @"numberAuthBusiness", @encode(id), @[]) ||
      !AFMethodMatches(number, @"isPresentedLoginVC", @encode(BOOL), @[]) ||
      !AFMethodMatches(number, @"cancelLoginVCAnimated:request:complete:", @encode(void),
                       @[ @(@encode(BOOL)), @"@", @"@?" ]))
    return NO;

  // Only instances owned by this bridge change class. No global method swizzle.
  @synchronized(self) {
    if (!AFTrackedNumberClass) {
      Class subclass = objc_allocateClassPair(number, "AFTrackedFusionNumberBusiness_1215", 0);
      if (!subclass)
        return NO;
      SEL selector = NSSelectorFromString(@"cancelLoginVCAnimated:request:complete:");
      Method method = class_getInstanceMethod(number, selector);
      if (!class_addMethod(subclass, selector, (IMP)AFTrackedCancel,
                           method_getTypeEncoding(method))) {
        objc_disposeClassPair(subclass);
        return NO;
      }
      objc_registerClassPair(subclass);
      AFTrackedNumberClass = subclass;
    }
  }
  return YES;
}

- (instancetype)initWithHandler:(id)handler {
  if (![AFSDKCleanup isSupported])
    return nil;
  self = [super init];
  if (!self)
    return nil;
  id business = AFObject(handler, @"business");
  if (object_getClass(business) != NSClassFromString(@"AlicomFusionBusiness"))
    return nil;
  id timer = AFObject(business, @"timerService");
  if (object_getClass(timer) != NSClassFromString(@"AlicomFusionTimerService"))
    return nil;
  id thread = AFObject(timer, @"threadService");
  if (object_getClass(thread) != NSClassFromString(@"AlicomFusionThreadService"))
    return nil;
  id number = AFObject(thread, @"numberAuthBusiness");
  Class numberClass = NSClassFromString(@"AlicomFusionNumberAuthBusiness");
  if (object_getClass(number) != numberClass)
    return nil;
  id queue = AFObject(business, @"inputQueue");
  if (![queue conformsToProtocol:@protocol(OS_dispatch_queue)])
    return nil;
  self.handler = handler;
  self.business = business;
  self.numberBusiness = number;
  self.inputQueue = queue;
  self.cancellations = dispatch_group_create();
  self.queuedCancellations = [NSMutableArray array];
  self.originalCancel = (AFCancelImplementation)class_getMethodImplementation(
      numberClass, NSSelectorFromString(@"cancelLoginVCAnimated:request:complete:"));
  objc_setAssociatedObject(number, &AFTrackerKey, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  object_setClass(number, AFTrackedNumberClass);
  return self;
}

- (void)cancelNumberBusiness:(id)number
                    selector:(SEL)selector
                    animated:(BOOL)animated
                     request:(id)request
                  completion:(void (^)(id))completion {
  dispatch_group_t group = self.cancellations;
  dispatch_group_enter(group);
  __weak AFSDKCleanup *weakSelf = self;
  dispatch_block_t enqueue = ^{
    [self.queuedCancellations addObject:^{
      AFSDKCleanup *tracker = weakSelf;
      if (!tracker) {
        dispatch_group_leave(group);
        return;
      }
      BOOL presented =
          ((BOOL (*)(id, SEL))objc_msgSend)(number, NSSelectorFromString(@"isPresentedLoginVC"));
      // The false branch has no side effects and never calls complete.
      if (!presented) {
        dispatch_group_leave(group);
        return;
      }
      tracker.cancelling = YES;
      NSObject *ticket = [[NSObject alloc] init];
      __block BOOL consumed = NO;
      tracker.originalCancel(number, selector, animated, request, ^(id response) {
        @synchronized(ticket) {
          if (consumed)
            return;
          consumed = YES;
        }
        // Wait for the entire vendor callback (including global cleanup) to
        // return. Ignore duplicate/late invocations before running vendor code.
        if (completion)
          completion(response);
        dispatch_block_t done = ^{
          tracker.cancelling = NO;
          dispatch_group_leave(group);
          [tracker drainCancellations];
        };
        if (NSThread.isMainThread)
          done();
        else
          dispatch_async(dispatch_get_main_queue(), done);
      });
    }];
    [self drainCancellations];
  };
  if (NSThread.isMainThread)
    enqueue();
  else
    dispatch_async(dispatch_get_main_queue(), enqueue);
}

- (void)drainCancellations {
  // PNS can store only one dismissal completion in its custom animation path.
  // Serialize actual dismissals, and check its flag on the same main queue as
  // its UIKit callback. A second queued cancel normally becomes a no-op.
  while (!self.cancelling && self.queuedCancellations.count) {
    dispatch_block_t cancel = self.queuedCancellations.firstObject;
    [self.queuedCancellations removeObjectAtIndex:0];
    cancel();
  }
}

- (void)destroyWithCompletion:(dispatch_block_t)completion {
  NSAssert(NSThread.isMainThread, @"Start cleanup on the main thread");
  if (self.destroying)
    return;
  self.destroying = YES;
  ((void (*)(id, SEL))objc_msgSend)(self.handler, NSSelectorFromString(@"destroy"));
  // 1.2.14's destroy enqueues a block on this serial inputQueue. That block
  // makes two carrier cancel calls; either can schedule a global-state cleanup
  // on the UIKit completion queue. The queue barrier alone is insufficient.
  dispatch_async(self.inputQueue, ^{
    // Graph/SMS UI work is queued on main from the destroy block. Reach main
    // after that work, then subscribe after all queued cancellation entries.
    dispatch_async(dispatch_get_main_queue(), ^{
      dispatch_group_notify(self.cancellations, dispatch_get_main_queue(), ^{
        id number = self.numberBusiness;
        if (object_getClass(number) == AFTrackedNumberClass) {
          object_setClass(number, class_getSuperclass(AFTrackedNumberClass));
          objc_setAssociatedObject(number, &AFTrackerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        self.handler = nil;
        self.business = nil;
        completion();
      });
    });
  });
}
@end
