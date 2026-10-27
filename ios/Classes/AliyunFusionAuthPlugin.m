#import "AliyunFusionAuthPlugin.h"
#import "AFSDKCleanup.h"
#import "AFLoginCard.h"
#import <AlicomFusionAuth/AlicomFusionAuth.h>
#import <SafariServices/SafariServices.h>

static NSString *AFRequiredString(id value) {
  if (![value isKindOfClass:NSString.class])
    return nil;
  NSString *string =
      [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  return string.length ? string : nil;
}

static NSString *AFProtocolTitle(NSString *title) {
  return [title hasPrefix:@"《"] && [title hasSuffix:@"》"]
             ? title
             : [NSString stringWithFormat:@"《%@》", title];
}

static BOOL AFValidAgreementURL(NSString *value) {
  if (!value.length)
    return NO;
  NSURLComponents *components = [NSURLComponents componentsWithString:value];
  return [components.scheme.lowercaseString isEqualToString:@"https"] &&
         components.host.length > 0 && components.URL != nil && components.user.length == 0 &&
         components.password.length == 0;
}

static UIViewController *AFTopController(UIViewController *controller) {
  while (controller) {
    if (controller.presentedViewController &&
        !controller.presentedViewController.isBeingDismissed) {
      controller = controller.presentedViewController;
    } else if ([controller isKindOfClass:UINavigationController.class]) {
      controller = ((UINavigationController *)controller).visibleViewController;
    } else if ([controller isKindOfClass:UITabBarController.class]) {
      controller = ((UITabBarController *)controller).selectedViewController;
    } else {
      return controller;
    }
  }
  return nil;
}

// Wait on UIKit's actual transition/dismissal completion; elapsed time is not
// evidence that the previous authentication UI has disappeared.
static void AFDismissOwnedController(UIViewController *controller, void (^completion)(BOOL)) {
  if (!controller) {
    completion(YES);
    return;
  }
  if (controller.isBeingPresented || controller.isBeingDismissed) {
    id<UIViewControllerTransitionCoordinator> transition = controller.transitionCoordinator;
    if ([transition
            animateAlongsideTransition:nil
                            completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
                              AFDismissOwnedController(controller, completion);
                            }])
      return;
    completion(NO);
    return;
  }
  if (controller.presentingViewController) {
    [controller dismissViewControllerAnimated:NO
                                   completion:^{
                                     completion(controller.presentingViewController == nil &&
                                                controller.viewIfLoaded.window == nil);
                                   }];
    return;
  }
  completion(controller.viewIfLoaded.window == nil);
}

// One delegate per invocation prevents late callbacks from affecting a newer attempt.
@interface AFFusionSession : NSObject <AlicomFusionAuthDelegate, AlicomFusionAuthUIDelegate>
@property (nonatomic, strong) AlicomFusionAuthHandler *handler;
@property (nonatomic, strong) AFSDKCleanup *cleanup;
@property (atomic, strong) AlicomFusionAuthToken *initialToken;
@property (nonatomic, copy) NSString *sceneId;
@property (atomic, copy) NSString *phoneNumber;
@property (nonatomic, copy) NSString *appName;
@property (nonatomic, copy) NSString *termsTitle;
@property (nonatomic, copy) NSString *termsURL;
@property (nonatomic, copy) NSString *privacyTitle;
@property (nonatomic, copy) NSString *privacyURL;
@property (nonatomic, copy) NSString *alternateLoginLabel;
@property (nonatomic, copy) NSString *phoneInputLabel;
@property (nonatomic, copy) NSString *emailLoginLabel;
@property (nonatomic, copy) NSDictionary *loginCard;
@property (nonatomic) BOOL appSms;
@property (nonatomic) BOOL startWithSms;
@property (nonatomic) BOOL smsReady;
@property (nonatomic) BOOL smsHandoffScheduled;
@property (nonatomic, copy) NSString *smsSessionId;
@property (nonatomic, strong) AlicomFusionVerifyCodeView *smsView;
@property (nonatomic, strong) UINavigationController *smsNavigation;
@property (nonatomic, copy) FlutterResult smsReply;
@property (nonatomic, copy) NSString *smsOperation;
@property (nonatomic, copy) NSString *smsRequestedPhone;
@property (nonatomic, copy) NSString *smsSentPhone;
@property (nonatomic) NSUInteger smsOperationId;
@property (nonatomic, strong) AFLoginCardControls *loginCardControls;
@property (nonatomic, strong) AFNumberPageLoading *numberPageLoading;
@property (nonatomic, assign) BOOL retainNumberPage;
@property (atomic, assign) BOOL numberPageRetained;
@property (nonatomic, assign) BOOL carrierConsent;
@property (nonatomic, weak) UIViewController *presenter;
@property (nonatomic, weak) UINavigationController *sdkNavigation;
@property (nonatomic, weak) SFSafariViewController *protocolController;
@property (nonatomic, copy) void (^completion)(id);
@property (nonatomic, copy) void (^stageChanged)(NSString *, dispatch_block_t);
@property (nonatomic, copy) dispatch_block_t cleanupDidFinish;
@property (nonatomic, strong) FlutterError *lastFailure;
@property (atomic, assign) BOOL finished;
@property (atomic, assign) BOOL inputRequested;
@property (atomic, assign) BOOL authenticated;
@property (nonatomic, assign) BOOL returnedInitialToken;
@property (nonatomic, assign) BOOL started;
@property (nonatomic, assign) BOOL cleanupComplete;
@property (nonatomic, strong) NSMutableArray<FlutterResult> *cancelReplies;
- (void)startWithToken:(NSString *)token schemeCode:(NSString *)schemeCode;
- (void)finish:(id)value;
- (void)cancelWithReply:(FlutterResult)reply;
- (void)chooseEmailLogin;
- (void)handleSmsCommand:(FlutterMethodCall *)call result:(FlutterResult)result;
- (void)handoffSms;
- (void)snapshotNumberPageWithReply:(FlutterResult)reply;
@end

// All access is on main. The vendor uses process-wide shared state, including
// across FlutterEngines; hold ownership through SDK and UIKit teardown.
static AFFusionSession *AFActiveSession;

@implementation AFFusionSession

- (void)snapshotNumberPageWithReply:(FlutterResult)reply {
  UIView *content = self.numberPageLoading.contentView;
  UIView *presenter = self.presenter.viewIfLoaded;
  if (self.finished || !self.numberPageRetained || !content.window || !presenter.window ||
      CGRectIsEmpty(content.bounds)) {
    reply([self error:@"number_page_unavailable" message:@"认证页面未就绪，请重试" event:nil]);
    return;
  }
  [content layoutIfNeeded];
  UIGraphicsImageRenderer *renderer =
      [[UIGraphicsImageRenderer alloc] initWithBounds:content.bounds];
  UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
    [content.layer renderInContext:context.CGContext];
  }];
  NSData *png = UIImagePNGRepresentation(image);
  if (!png.length) {
    reply([self error:@"snapshot_failed" message:@"无法准备登录过渡，请重试" event:nil]);
    return;
  }
  CGRect frame;
  if (content.window == presenter.window) {
    frame = [content convertRect:content.bounds toView:presenter];
  } else {
    CGRect inWindow = [content convertRect:content.bounds toView:content.window];
    CGRect inPresenterWindow = [content.window convertRect:inWindow toWindow:presenter.window];
    frame = [presenter convertRect:inPresenterWindow fromView:presenter.window];
  }
  reply(@{
    @"png" : [FlutterStandardTypedData typedDataWithBytes:png],
    @"x" : @(frame.origin.x),
    @"y" : @(frame.origin.y),
    @"width" : @(frame.size.width),
    @"height" : @(frame.size.height)
  });
}

- (void)notifyStage:(NSString *)stage completion:(dispatch_block_t)completion {
  if (self.finished)
    return;
  if (self.stageChanged)
    self.stageChanged(stage, completion);
  else if (completion)
    completion();
}

- (void)resolveSms:(id)value {
  FlutterResult reply = self.smsReply;
  self.smsReply = nil;
  self.smsOperation = nil;
  self.smsRequestedPhone = nil;
  self.smsOperationId++;
  if (reply)
    reply(value);
}

- (void)handoffSms {
  if (!self.appSms || !self.smsView || !self.sdkNavigation || self.smsReady ||
      self.smsHandoffScheduled || self.finished)
    return;
  self.smsHandoffScheduled = YES;
  // Keep the SDK's public SMS view/controller alive, but return presentation
  // to the existing Flutter form. Dismissing UIKit UI does not stop the scene.
  self.smsNavigation = self.sdkNavigation;
  [self notifyStage:@"smsSwitching"
         completion:^{
           if (self.finished)
             return;
           // Flutter has removed its number-loading placeholder before UIKit exposes it.
           self.smsNavigation.view.hidden = YES;
           dispatch_async(dispatch_get_main_queue(), ^{
             [self handoffSmsWhenPresentedBefore:NSProcessInfo.processInfo.systemUptime + 2];
           });
         }];
}

- (void)handoffSmsWhenPresentedBefore:(NSTimeInterval)deadline {
  if (self.finished)
    return;
  self.smsNavigation = self.sdkNavigation;
  self.smsNavigation.view.hidden = YES;
  // Customization can run before presentation. Wait for UIKit evidence so a
  // later SDK presentation cannot cover the Flutter form after handoff.
  if (!self.smsNavigation.presentingViewController && !self.smsNavigation.viewIfLoaded.window) {
    if (NSProcessInfo.processInfo.systemUptime >= deadline) {
      [self finish:[self error:@"sms_ui_unavailable"
                       message:@"短信认证页面未就绪，请重试"
                         event:nil]];
      return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 16 * NSEC_PER_MSEC), dispatch_get_main_queue(),
                   ^{
                     [self handoffSmsWhenPresentedBefore:deadline];
                   });
    return;
  }
  AFDismissOwnedController(self.smsNavigation, ^(BOOL dismissed) {
    self.smsHandoffScheduled = NO;
    if (self.finished)
      return;
    if (!dismissed) {
      [self finish:[self error:@"sms_ui_unavailable"
                       message:@"无法返回短信输入页面，请重试"
                         event:nil]];
      return;
    }
    self.smsReady = YES;
    self.smsSessionId = NSUUID.UUID.UUIDString;
    [self deliver:[FlutterError errorWithCode:@"app_sms_ready"
                                      message:@"请输入手机号"
                                      details:@{@"sessionId" : self.smsSessionId}]];
  });
}

- (void)handleSmsCommand:(FlutterMethodCall *)call result:(FlutterResult)result {
  NSDictionary *args = [call.arguments isKindOfClass:NSDictionary.class] ? call.arguments : @{};
  if (self.finished || !self.smsReady || !self.smsView ||
      ![self.smsSessionId isEqual:args[@"sessionId"]]) {
    result([self error:@"sms_session_expired"
               message:@"短信认证已过期，请重新获取验证码"
                 event:nil]);
    return;
  }
  if (![args[@"privacyAccepted"] isEqual:@YES]) {
    result([self error:@"privacy_not_accepted" message:@"请先阅读并勾选同意下方协议" event:nil]);
    return;
  }
  NSString *phone = AFRequiredString(args[@"phone"]);
  NSString *code = AFRequiredString(args[@"code"]);
  BOOL sending = [call.method isEqual:@"sendSmsCode"];
  NSPredicate *phonePattern =
      [NSPredicate predicateWithFormat:@"SELF MATCHES %@", @"1[3-9][0-9]{9}"];
  NSPredicate *codePattern = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", @"[0-9]{4,8}"];
  if (![phonePattern evaluateWithObject:phone] ||
      (!sending &&
       (![codePattern evaluateWithObject:code] || ![phone isEqual:self.smsSentPhone]))) {
    result([self error:@"invalid_arguments" message:@"请为当前手机号获取验证码后再提交" event:nil]);
    return;
  }
  if (self.smsReply) {
    result([self error:@"busy" message:@"短信认证正在进行，请稍候" event:nil]);
    return;
  }
  self.smsReply = result;
  self.smsOperation = sending ? @"send" : @"verify";
  if (sending)
    self.smsSentPhone = nil;
  self.smsRequestedPhone = phone;
  NSUInteger operationId = ++self.smsOperationId;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
    if (!self.finished && self.smsReply && self.smsOperationId == operationId) {
      [self finish:[self error:@"timeout" message:@"短信认证超时，请重新获取验证码" event:nil]];
    }
  });
  self.phoneNumber = phone;
  self.smsView.phoneTextField.text = phone;
  self.smsView.checkBoxBtn.selected = YES;
  if (sending)
    [self.smsView verifyCodeBtnClick:phone checked:YES];
  else
    [self.smsView submitVerifyCodeBtnClick:phone code:code];
}

- (void)chooseEmailLogin {
  [self chooseInput:@"email_login" message:@"请输入邮箱验证码登录"];
}

- (void)chooseInput:(NSString *)code message:(NSString *)message {
  if (self.finished || self.inputRequested)
    return;
  self.inputRequested = YES;
  // Leave the SDK callback stack before cancelling its controller/session.
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!self.finished)
      [self finish:[self error:code message:message event:nil]];
  });
}

- (BOOL)acceptsHandler:(AlicomFusionAuthHandler *)handler {
  return !self.finished && !self.inputRequested && self.handler == handler;
}

- (FlutterError *)error:(NSString *)code
                message:(NSString *)message
                  event:(AlicomFusionEvent *)event {
  NSMutableDictionary *details = [NSMutableDictionary dictionary];
  // Do not return vendor payloads: some contain phone numbers or authentication tokens.
  if (event.resultCode.length)
    details[@"sdkCode"] = event.resultCode;
  if (event.innerCode.length)
    details[@"innerCode"] = event.innerCode;
  if (event.requestId.length)
    details[@"requestId"] = event.requestId;
  return [FlutterError errorWithCode:code message:message details:details];
}

- (void)startWithToken:(NSString *)token schemeCode:(NSString *)schemeCode {
  // Called only after the explicit Dart authenticate request and consent UI.
  [AlicomFusionLog logEnable:NO];
  [AlicomFusionAuthHandler useSDKSupplyUMSDK:NO];
  self.initialToken = [[AlicomFusionAuthToken alloc] initWithTokenStr:token];
  self.handler = [[AlicomFusionAuthHandler alloc] initWithToken:self.initialToken
                                                     schemeCode:schemeCode];
  self.cleanup = [[AFSDKCleanup alloc] initWithHandler:self.handler];
  if (!self.cleanup) {
    self.finished = YES;
    // Class/ABI checks ran before constructing the handler. An unexpected
    // instance graph is rejected before setting the delegate or starting auth.
    // Keep process ownership because cleanup cannot be proven on this instance.
    [self deliver:[self error:@"sdk_cleanup_unavailable"
                      message:@"当前融合认证SDK实例不支持安全清理，请检查内置SDK版本"
                        event:nil]];
    return;
  }
  [self.handler setFusionAuthDelegate:self];
  __weak AFFusionSession *weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 65 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
    AFFusionSession *session = weakSelf;
    if (session && !session.finished && !session.authenticated) {
      [session finish:[session error:@"auth_timeout"
                             message:@"融合认证初始化超时，请重试"
                               event:nil]];
    }
  });
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 295 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
    AFFusionSession *session = weakSelf;
    if (session && !session.finished) {
      [session finish:[session error:@"timeout" message:@"认证已超时，请重新发起" event:nil]];
    }
  });
}

- (void)finish:(id)value {
  NSAssert(NSThread.isMainThread, @"Authentication cleanup must run on the main thread");
  if (self.finished)
    return;
  self.finished = YES;
  // Keep the loading button and input shield until UIKit has actually closed.
  // Teardown can span multiple frames; removing it here exposes the old button.
  [self resolveSms:[value isKindOfClass:FlutterError.class] ? value
                                                            : [self error:@"cancelled"
                                                                  message:@"认证已结束"
                                                                    event:nil]];
  // Mark finished before stopping: the vendor may synchronously send finish callbacks.
  self.initialToken = nil;
  self.phoneNumber = nil;
  __weak AFFusionSession *weakSelf = self;
  // A deadline reports failure; it NEVER releases ownership as a timing guess.
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
    AFFusionSession *session = weakSelf;
    if (session && !session.cleanupComplete) {
      [session deliver:[session error:@"sdk_cleanup_timeout"
                              message:@"认证窗口清理尚未完成，请稍后重试"
                                event:nil]];
    }
  });
  AFDismissOwnedController(self.protocolController, ^(BOOL dismissed) {
    if (!dismissed) {
      [self deliver:[self error:@"sdk_cleanup_failed"
                        message:@"认证协议窗口尚未关闭，请稍后重试"
                          event:nil]];
      return;
    }
    [self.handler closeNumberAuthPrivactAlertView];
    if (self.started)
      [self.handler stopSceneWithTemplateId:self.sceneId];
    [self.cleanup destroyWithCompletion:^{
      AFDismissOwnedController(self.sdkNavigation, ^(BOOL SDKUIDismissed) {
        if (!SDKUIDismissed) {
          [self deliver:[self error:@"sdk_cleanup_failed"
                            message:@"认证窗口尚未关闭，请稍后重试"
                              event:nil]];
          return;
        }
        self.cleanupComplete = YES;
        self.smsView = nil;
        self.smsNavigation = nil;
        self.smsSentPhone = nil;
        self.smsSessionId = nil;
        self.handler = nil;
        self.cleanup = nil;
        [self.numberPageLoading invalidate];
        self.numberPageLoading = nil;
        self.loginCardControls = nil;
        self.stageChanged = nil;
        if (AFActiveSession == self)
          AFActiveSession = nil;
        dispatch_block_t cleanupDidFinish = self.cleanupDidFinish;
        self.cleanupDidFinish = nil;
        if (cleanupDidFinish)
          cleanupDidFinish();
        [self deliver:value];
      });
    }];
  });
}

- (void)deliver:(id)value {
  void (^completion)(id) = self.completion;
  self.completion = nil;
  if (completion)
    completion(value);
  NSArray<FlutterResult> *replies = self.cancelReplies.copy;
  [self.cancelReplies removeAllObjects];
  for (FlutterResult reply in replies) {
    reply(self.cleanupComplete ? nil : value);
  }
}

- (void)cancelWithReply:(FlutterResult)reply {
  if (self.cleanupComplete) {
    reply(nil);
    return;
  }
  if (!self.cancelReplies)
    self.cancelReplies = [NSMutableArray array];
  [self.cancelReplies addObject:[reply copy]];
  if (self.finished && !self.completion) {
    [self deliver:[self error:@"sdk_cleanup_pending"
                      message:@"上一认证流程仍在清理，请稍后重试"
                        event:nil]];
    return;
  }
  [self finish:[self error:@"cancelled" message:@"已取消手机认证" event:nil]];
}

- (void)promptForCarrierConsent {
  if (self.finished || self.inputRequested || self.loginCardControls.consentPromptButton.hidden)
    return;
  [self showMessage:@"请先阅读并勾选同意下方协议"];
}

- (void)showMessage:(NSString *)message {
  UIViewController *controller = AFTopController(self.presenter);
  if (!controller.view.window || !message.length)
    return;
  UIView *container = [[UIView alloc] init];
  container.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.8];
  container.layer.cornerRadius = 10;
  container.translatesAutoresizingMaskIntoConstraints = NO;
  UILabel *label = [[UILabel alloc] init];
  label.text = message;
  label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
  label.adjustsFontForContentSizeCategory = YES;
  label.textColor = UIColor.whiteColor;
  label.textAlignment = NSTextAlignmentCenter;
  label.numberOfLines = 0;
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.accessibilityTraits = UIAccessibilityTraitStaticText;
  [container addSubview:label];
  [controller.view addSubview:container];
  CGFloat width = MIN(420, MAX(0, controller.view.bounds.size.width - 48));
  [NSLayoutConstraint activateConstraints:@[
    [container.centerXAnchor constraintEqualToAnchor:controller.view.centerXAnchor],
    [container.centerYAnchor constraintEqualToAnchor:controller.view.centerYAnchor],
    [container.widthAnchor constraintEqualToConstant:width],
    [container.heightAnchor constraintGreaterThanOrEqualToConstant:52],
    [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:20],
    [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-20],
    [label.topAnchor constraintEqualToAnchor:container.topAnchor constant:15],
    [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-15]
  ]];
  UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, message);
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
    [container removeFromSuperview];
  });
}

#pragma mark - Core SDK callbacks (not guaranteed to arrive on the main queue)

- (AlicomFusionAuthToken *)onSDKTokenUpdate:(AlicomFusionAuthHandler *)handler {
  // This callback is synchronous. Never block it waiting on Dart or a network request.
  // The vendor header declares nonnull, but its documented token-update retry
  // path accepts no token. Return nil while cancellation is queued, never an old token.
  @synchronized(self) {
    if (self.finished || self.numberPageRetained)
      return nil;
    if (!self.authenticated && !self.returnedInitialToken) {
      self.returnedInitialToken = YES;
      return self.initialToken;
    }
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    if ([self acceptsHandler:handler] && !self.numberPageRetained) {
      [self finish:[self error:@"auth_token_expired"
                       message:@"认证凭证已过期，请重新发起以获取新凭证"
                         event:nil]];
    }
  });
  return nil;
}

- (void)onSDKTokenAuthSuccess:(AlicomFusionAuthHandler *)handler {
  // Defer start out of the SDK callback stack; it can notify success more than once.
  dispatch_async(dispatch_get_main_queue(), ^{
    if (![self acceptsHandler:handler] || self.started)
      return;
    self.authenticated = YES;
    if (!self.presenter.view.window) {
      [self finish:[self error:@"no_view_controller"
                       message:@"当前页面不可显示认证窗口，请返回后重试"
                         event:nil]];
      return;
    }
    self.started = YES;
    [handler setInterfaceOrientation:UIInterfaceOrientationMaskPortrait];
    [handler startSceneUIWithTemplateId:self.sceneId viewController:self.presenter delegate:self];
  });
}

- (void)onSDKTokenAuthFailure:(AlicomFusionAuthHandler *)handler
                    failToken:(AlicomFusionAuthToken *)failToken
                        error:(AlicomFusionEvent *)error {
  dispatch_async(dispatch_get_main_queue(), ^{
    if ([self acceptsHandler:handler] && !self.numberPageRetained) {
      [self finish:[self error:@"auth_token_invalid"
                       message:@"融合认证鉴权失败，请重试；若持续失败请检查认证方案配置"
                         event:error]];
    }
  });
}

- (void)onVerifySuccess:(AlicomFusionAuthHandler *)handler
               nodeName:(NSString *)nodeName
              maskToken:(NSString *)maskToken
                  event:(AlicomFusionEvent *)event {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (![self acceptsHandler:handler] || self.numberPageRetained)
      return;
    if (!maskToken.length) {
      [self finish:[self error:@"empty_verify_token"
                       message:@"未获取到认证凭证，请重试"
                         event:event]];
      return;
    }
    if (self.appSms && self.smsReady) {
      if ([self.smsOperation isEqual:@"verify"])
        [self resolveSms:@{@"verifyToken" : maskToken}];
      return;
    }
    if (self.retainNumberPage && [nodeName isEqual:AlicomFusionNodeNameNumberAuth]) {
      self.numberPageRetained = YES;
      [self.numberPageLoading setAuthorizing:YES];
      // Return proof without tearing down the visible page. The application
      // owns the remaining server/navigation work and cancels this session on exit.
      [self notifyStage:@"authorizing"
             completion:^{
               if (![self acceptsHandler:handler])
                 return;
               [self deliver:@{@"verifyToken" : maskToken, @"numberPageRetained" : @YES}];
             }];
      return;
    }
    // A native success only yields a proof. The server must verify it before login/reset.
    [self finish:@{@"verifyToken" : maskToken}];
  });
}

- (void)onHalfwayVerifySuccess:(AlicomFusionAuthHandler *)handler
                      nodeName:(NSString *)nodeName
                     maskToken:(NSString *)maskToken
                         event:(AlicomFusionEvent *)event
                   resultBlock:(void (^)(BOOL))resultBlock {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (![self acceptsHandler:handler])
      return;
    // This belongs to change-phone flows, which are deliberately not exposed here.
    // Never acknowledge an intermediate proof without server verification.
    if (resultBlock)
      resultBlock(NO);
    [self finish:[self error:@"unsupported_intermediate_verification"
                     message:@"该认证方案包含不支持的中间校验，请检查场景配置"
                       event:event]];
  });
}

- (void)onVerifyFailed:(AlicomFusionAuthHandler *)handler
              nodeName:(NSString *)nodeName
                 error:(AlicomFusionEvent *)error {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (![self acceptsHandler:handler])
      return;
    if (self.numberPageRetained)
      return;
    [self.numberPageLoading setAuthorizing:NO];
    if (self.appSms && self.smsReady) {
      [self
          resolveSms:[self error:@"sms_failed"
                         message:error.resultMsg.length ? error.resultMsg : @"短信认证失败，请重试"
                           event:error]];
      return;
    }
    self.lastFailure = [self error:@"verification_failed"
                           message:@"手机认证未通过，请重试"
                             event:error];
    if ([nodeName isEqualToString:AlicomFusionNodeNameVerifyCodeAuth]) {
      if ([error.resultCode isEqualToString:AlicomFusionVerifyCodeAutoNumberShowFail]) {
        [self finish:[self error:@"phone_number_required"
                         message:@"请先填写要验证的手机号"
                           event:error]];
      } else if ([error.resultCode isEqualToString:AlicomFusionVerifyCodeFrequency] ||
                 [error.resultCode isEqualToString:AlicomFusionVerifyCodeRisk] ||
                 [error.resultCode isEqualToString:AlicomFusionVerifyCodeInitFail] ||
                 [error.resultCode isEqualToString:AlicomFusionVerifyCodeShowFail]) {
        [handler continueSceneWithTemplateId:self.sceneId isSuccess:NO];
      } else {
        // A wrong/expired code is recoverable on the same default SDK screen.
        [self
            showMessage:error.resultMsg.length ? error.resultMsg : @"验证码校验失败，请检查后重试"];
      }
    } else {
      // No SIM / carrier failure can advance to the server-configured SMS fallback.
      [handler continueSceneWithTemplateId:self.sceneId isSuccess:NO];
    }
  });
}

- (void)onTemplateFinish:(AlicomFusionAuthHandler *)handler event:(AlicomFusionEvent *)event {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (![self acceptsHandler:handler])
      return;
    if (self.numberPageRetained)
      return;
    if ([event.resultCode isEqualToString:AlicomFusionAuthNextNodeFail]) {
      [self finish:self.lastFailure
                       ?: [self error:@"verification_failed"
                              message:@"没有可用的认证方式，请稍后重试"
                                event:event]];
    } else if ([event.resultCode isEqualToString:AlicomFusionTemplateEndSuccess]) {
      [self finish:[self error:@"missing_verify_token"
                       message:@"认证流程已结束但未返回有效凭证，请重试"
                         event:event]];
    } else {
      [self finish:[self error:@"cancelled" message:@"已取消手机认证" event:event]];
    }
  });
}

- (NSString *)onGetPhoneNumberForVerification:(AlicomFusionAuthHandler *)handler
                                        event:(AlicomFusionEvent *)event {
  return self.finished ? @"" : (self.phoneNumber ?: @"");
}

- (void)onProtocolClick:(AlicomFusionAuthHandler *)handler
           protocolName:(NSString *)protocolName
            protocolUrl:(NSString *)protocolUrl
                  event:(AlicomFusionEvent *)event {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (![self acceptsHandler:handler])
      return;
    NSURL *url = [NSURL URLWithString:protocolUrl];
    NSString *scheme = url.scheme.lowercaseString;
    if (!url.host.length ||
        (![@"https" isEqualToString:scheme] && ![@"http" isEqualToString:scheme])) {
      [self showMessage:@"暂时无法打开协议，请稍后重试"];
      return;
    }
    UIViewController *top = AFTopController(self.presenter);
    if (!top.view.window || [top isKindOfClass:SFSafariViewController.class])
      return;
    SFSafariViewController *browser = [[SFSafariViewController alloc] initWithURL:url];
    self.protocolController = browser;
    [top presentViewController:browser animated:YES completion:nil];
  });
}

- (void)onVerifyInterrupt:(AlicomFusionAuthHandler *)handler event:(AlicomFusionEvent *)event {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (![self acceptsHandler:handler] || self.numberPageRetained)
      return;
    if ([event.resultCode isEqualToString:AlicomFusionStartLoading] ||
        [event.resultCode isEqualToString:AlicomFusionEndLoading])
      return;
    if (self.appSms && self.smsReady && self.smsReply) {
      [self
          resolveSms:[self error:@"sms_failed"
                         message:event.resultMsg.length ? event.resultMsg : @"请检查手机号或验证码"
                           event:event]];
      return;
    }
    if ([event.resultCode isEqualToString:AlicomFusionTemplateNotExist] ||
        [event.resultCode isEqualToString:AlicomFusionErrorSchemeCodeEmpty]) {
      [self finish:[self error:@"invalid_configuration"
                       message:@"融合认证场景未配置，请联系管理员"
                         event:event]];
    } else {
      [self showMessage:[event.resultMsg containsString:@"协议"]
                            ? @"请先阅读并勾选同意下方协议"
                            : (event.resultMsg.length ? event.resultMsg
                                                      : @"请检查手机号并阅读、同意相关协议")];
    }
  });
}

- (void)onAuthEvent:(AlicomFusionAuthHandler *)handler eventData:(AlicomFusionEvent *)event {
  if ([event.resultCode isEqual:AlicomFusionNumberAuthPresentSuccess] ||
      [event.resultCode isEqual:AlicomFusionNumberAuthOtherPhoneLoginClickEvent]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (![self acceptsHandler:handler])
        return;
      if ([event.resultCode isEqual:AlicomFusionNumberAuthPresentSuccess]) {
        if (!self.startWithSms)
          [self notifyStage:@"numberReady" completion:nil];
      } else if (self.appSms) {
        [self notifyStage:@"smsSwitching" completion:nil];
      }
    });
    return;
  }
  if ([event.resultCode isEqual:AlicomFusionVerifyCodeGetSuccess]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if ([self acceptsHandler:handler] && [self.smsOperation isEqual:@"send"]) {
        self.smsSentPhone = self.smsRequestedPhone;
        [self resolveSms:nil];
      }
    });
    return;
  }
  if (![event.resultCode isEqualToString:AlicomFusionNumberAuthGetTokenEvent] ||
      (![event.innerCode
           isEqualToString:AlicomFusionNumberAuthCodeLoginControllerClickCheckBoxBtn] &&
       ![event.innerCode isEqualToString:AlicomFusionNumberAuthCodeLoginControllerClickLoginBtn]))
    return;
  id selected = event.extendData[@"isCheckBoxSelected"];
  BOOL accepted = ([selected isKindOfClass:NSNumber.class] && [selected isEqual:@1]) ||
                  ([selected isKindOfClass:NSString.class] && [selected isEqualToString:@"1"]);
  // The SDK callback is notification-only. Update our UI on the next main turn.
  dispatch_async(dispatch_get_main_queue(), ^{
    if ([self acceptsHandler:handler]) {
      if ([event.innerCode isEqual:AlicomFusionNumberAuthCodeLoginControllerClickLoginBtn]) {
        if (self.retainNumberPage && (accepted || self.carrierConsent)) {
          [self.numberPageLoading setAuthorizing:YES];
          [self notifyStage:@"authorizing" completion:nil];
        }
        return;
      }
      self.carrierConsent = accepted;
      [self.loginCardControls setCarrierConsent:accepted];
    }
  });
}

#pragma mark - SDK authorization UI and application agreements

- (void)onPhoneNumberVerifyUICustomDefined:(AlicomFusionAuthHandler *)handler
                                templateId:(NSString *)templateId
                                    nodeId:(NSString *)nodeId
                                   UIModel:(AlicomFusionNumberAuthModel *)model {
  if (![self acceptsHandler:handler])
    return;
  model.navTitle = [[NSAttributedString alloc] initWithString:self.appName];
  // These are the SDK's application agreement slots. Its carrier agreement,
  // operator link and operator wording remain managed by the SDK.
  model.privacyOne = @[ AFProtocolTitle(self.termsTitle), self.termsURL ];
  model.privacyTwo = @[ AFProtocolTitle(self.privacyTitle), self.privacyURL ];
  model.privacyPreText = @"我已阅读并同意";
  model.privacyOperatorPreText = @"《";
  model.privacyOperatorSufText = @"》";
  // The public whole-paragraph font also applies to each linked protocol title.
  model.privacyFont = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
  model.checkBoxIsChecked = NO;
  model.checkBoxIsHidden = NO;
  // Apply the same number-page presentation when the inline card cannot fit.
  model.sloganIsHidden = YES;
  model.privacyAlertTitleContent = @"请先阅读并勾选同意下方协议";
  model.privacyAlertTitleFont = [UIFont systemFontOfSize:15];
  model.privacyAlertFrameBlock = ^CGRect(CGSize screen, CGSize parent, CGRect frame) {
    CGFloat width = MIN(420, MAX(0, parent.width - 48));
    return CGRectMake((parent.width - width) / 2, frame.origin.y, width, frame.size.height);
  };
  model.numberFrameBlock = ^CGRect(CGSize screen, CGSize parent, CGRect frame) {
    return CGRectMake((parent.width - frame.size.width) / 2, frame.origin.y, frame.size.width,
                      frame.size.height);
  };
  if ([self.sceneId isEqualToString:AlicomFusionTemplateId_100001]) {
    NSDictionary *attributes =
        model.loginBtnText.length ? [model.loginBtnText attributesAtIndex:0 effectiveRange:nil] : @{
          NSFontAttributeName : [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold],
          NSForegroundColorAttributeName : UIColor.whiteColor
        };
    model.loginBtnText = [[NSAttributedString alloc] initWithString:@"本机号码一键登录"
                                                         attributes:attributes];
  }
  if (self.appSms && self.startWithSms) {
    model.customViewBlock = ^(UIView *parent) {
      parent.hidden = YES;
    };
    dispatch_async(dispatch_get_main_queue(), ^{
      if ([self acceptsHandler:handler])
        [model otherPhoneLogin];
    });
    return;
  }
  if (self.phoneInputLabel.length) {
    UIButton *change = [UIButton buttonWithType:UIButtonTypeSystem];
    [change setTitle:self.phoneInputLabel forState:UIControlStateNormal];
    // A custom switch button must call the SDK's public action to continue
    // its configured SMS flow and return the same kind of fusion proof.
    [change addTarget:model
                  action:@selector(otherPhoneLogin)
        forControlEvents:UIControlEventTouchUpInside];
    model.otherLoginButton = change;
  }
  if (self.alternateLoginLabel.length) {
    model.changeBtnTitle = [[NSAttributedString alloc] initWithString:self.alternateLoginLabel];
    model.changeBtnIsHidden = NO;
    __weak AFFusionSession *weakSelf = self;
    __weak AlicomFusionAuthHandler *weakHandler = handler;
    model.moreLoginActionBlock = ^{
      dispatch_block_t chooseAlternative = ^{
        AFFusionSession *session = weakSelf;
        AlicomFusionAuthHandler *activeHandler = weakHandler;
        if (!activeHandler || ![session acceptsHandler:activeHandler])
          return;
        [session finish:[session error:@"alternative_login"
                               message:@"已切换到其他登录方式"
                                 event:nil]];
      };
      dispatch_async(dispatch_get_main_queue(), chooseAlternative);
    };
  }
  if (self.loginCard) {
    self.loginCardControls = AFConfigureLoginCard(model, self.loginCard, self.emailLoginLabel);
    [self.loginCardControls.consentPromptButton addTarget:self
                                                   action:@selector(promptForCarrierConsent)
                                         forControlEvents:UIControlEventTouchUpInside];
    [self.loginCardControls.emailButton addTarget:self
                                           action:@selector(chooseEmailLogin)
                                 forControlEvents:UIControlEventTouchUpInside];
  } else if (self.emailLoginLabel.length) {
    UIButton *email = [UIButton buttonWithType:UIButtonTypeSystem];
    [email setTitle:self.emailLoginLabel forState:UIControlStateNormal];
    [email addTarget:self
                  action:@selector(chooseEmailLogin)
        forControlEvents:UIControlEventTouchUpInside];
    model.customViewBlock = ^(UIView *parent) {
      [parent addSubview:email];
    };
    model.customViewLayoutBlock =
        ^(CGSize screen, CGRect content, CGRect name, CGRect other, CGRect nav, CGRect title,
          CGRect logo, CGRect slogan, CGRect number, CGRect login, CGRect change, CGRect privacy) {
          email.frame = CGRectMake(MAX(16, content.size.width - 156), CGRectGetMaxY(nav), 140, 44);
        };
  }
  if (self.retainNumberPage)
    self.numberPageLoading = AFConfigureNumberPageLoading(model);
}

- (void)onSMSCodeVerifyUICustomDefined:(AlicomFusionAuthHandler *)handler
                            templateId:(NSString *)templateId
                                nodeId:(NSString *)nodeId
                           isAutoInput:(BOOL)isAutoInput
                                  view:(AlicomFusionVerifyCodeView *)view {
  if (![self acceptsHandler:handler])
    return;
  if (self.appSms) {
    self.smsView = view;
    view.checkBoxBtn.selected = NO;
    view.hidden = YES;
    [self handoffSms];
    return;
  }
  view.titleString = [NSString stringWithFormat:@"%@手机验证", self.appName];
  view.checkBoxBtn.selected = NO;
  if (!isAutoInput && self.phoneNumber.length)
    view.phoneTextField.text = self.phoneNumber;
  if (![templateId isEqualToString:AlicomFusionTemplateId_100001])
    return;
  // Preserve all vendor agreements and its UITextView delegate/link handling.
  NSMutableAttributedString *text = [view.privacyTextView.attributedText mutableCopy];
  if (!text.length)
    text = [[NSMutableAttributedString alloc] initWithString:@"我已阅读并同意"];
  NSDictionary *attributes = @{
    NSFontAttributeName : view.privacyTextView.font ?: [UIFont systemFontOfSize:12],
    NSForegroundColorAttributeName : view.privacyTextView.textColor ?: UIColor.labelColor
  };
  [text appendAttributedString:[[NSAttributedString alloc] initWithString:@"、"
                                                               attributes:attributes]];
  NSMutableDictionary *linkAttributes = [attributes mutableCopy];
  linkAttributes[NSLinkAttributeName] = [NSURL URLWithString:self.termsURL];
  [text appendAttributedString:[[NSAttributedString alloc]
                                   initWithString:[NSString
                                                      stringWithFormat:@"《%@》", self.termsTitle]
                                       attributes:linkAttributes]];
  [text appendAttributedString:[[NSAttributedString alloc] initWithString:@"和"
                                                               attributes:attributes]];
  linkAttributes[NSLinkAttributeName] = [NSURL URLWithString:self.privacyURL];
  [text appendAttributedString:[[NSAttributedString alloc]
                                   initWithString:[NSString
                                                      stringWithFormat:@"《%@》", self.privacyTitle]
                                       attributes:linkAttributes]];
  view.privacyTextView.attributedText = text;
}

- (void)onNavigationControllerCustomDefined:(AlicomFusionAuthHandler *)handler
                                 templateId:(NSString *)templateId
                                     nodeId:(NSString *)nodeId
                                 navigation:(UINavigationController *)naviController {
  if (self.handler == handler) {
    self.sdkNavigation = naviController;
    if (self.appSms) {
      naviController.modalPresentationStyle = UIModalPresentationOverFullScreen;
      [self handoffSms];
    }
  }
}
@end

@interface AliyunFusionAuthPlugin ()
@property (nonatomic, weak) NSObject<FlutterPluginRegistrar> *registrar;
@property (nonatomic, strong) FlutterMethodChannel *channel;
@property (nonatomic, strong) AFFusionSession *session;
@end

@implementation AliyunFusionAuthPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  AliyunFusionAuthPlugin *plugin = [[AliyunFusionAuthPlugin alloc] init];
  plugin.registrar = registrar;
  plugin.channel = [FlutterMethodChannel methodChannelWithName:@"aliyun_fusion_auth"
                                               binaryMessenger:registrar.messenger];
  [registrar addMethodCallDelegate:plugin channel:plugin.channel];
  [registrar publish:plugin];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (![NSThread isMainThread]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self handleMethodCall:call result:result];
    });
    return;
  }
  if ([call.method isEqualToString:@"capabilities"]) {
    // iOS already hosts the vendor scene in the Flutter-owned view controller.
    result(@{@"flutterHosted" : @YES});
    return;
  }
  if ([call.method isEqualToString:@"cancel"]) {
    if (self.session)
      [self.session cancelWithReply:result];
    else
      result(nil);
    return;
  }
  if ([call.method isEqual:@"snapshotNumberPage"]) {
    if (self.session)
      [self.session snapshotNumberPageWithReply:result];
    else
      result([FlutterError errorWithCode:@"number_page_unavailable"
                                 message:@"认证页面已关闭"
                                 details:nil]);
    return;
  }
  if ([call.method isEqual:@"sendSmsCode"] || [call.method isEqual:@"submitSmsCode"]) {
    if (self.session)
      [self.session handleSmsCommand:call result:result];
    else
      result([FlutterError errorWithCode:@"sms_session_expired"
                                 message:@"短信认证已过期，请重新获取验证码"
                                 details:nil]);
    return;
  }
  if (![call.method isEqualToString:@"authenticate"]) {
    result(FlutterMethodNotImplemented);
    return;
  }
  if (AFActiveSession) {
    result([FlutterError errorWithCode:@"busy" message:@"已有认证流程正在进行" details:nil]);
    return;
  }
  NSDictionary *args = [call.arguments isKindOfClass:NSDictionary.class] ? call.arguments : @{};
  id privacyAccepted = args[@"privacyAccepted"];
  BOOL nativeConsent = [args[@"deferConsentToNative"] isEqual:@YES] &&
                       [args[@"sceneId"] isEqual:AlicomFusionTemplateId_100001];
  if (![privacyAccepted isKindOfClass:NSNumber.class] ||
      CFGetTypeID((__bridge CFTypeRef)privacyAccepted) != CFBooleanGetTypeID() ||
      (![privacyAccepted boolValue] && !nativeConsent)) {
    result([FlutterError errorWithCode:@"privacy_not_accepted"
                               message:@"请先阅读并勾选同意下方协议"
                               details:nil]);
    return;
  }
  NSString *token = AFRequiredString(args[@"authToken"]);
  NSString *scheme = AFRequiredString(args[@"schemeCode"]);
  NSString *scene = AFRequiredString(args[@"sceneId"]);
  NSString *phone = AFRequiredString(args[@"phoneNumber"]);
  NSString *appName = AFRequiredString(args[@"appName"]);
  NSString *termsTitle = AFRequiredString(args[@"termsTitle"]);
  NSString *termsURL = AFRequiredString(args[@"termsUrl"]);
  NSString *privacyTitle = AFRequiredString(args[@"privacyTitle"]);
  NSString *privacyURL = AFRequiredString(args[@"privacyUrl"]);
  NSString *alternateLoginLabel = AFRequiredString(args[@"alternateLoginLabel"]);
  NSString *phoneInputLabel = AFRequiredString(args[@"phoneInputLabel"]);
  NSString *emailLoginLabel = AFRequiredString(args[@"emailLoginLabel"]);
  NSDictionary *loginCard = args[@"loginCard"];
  BOOL supportedScene = [scene isEqualToString:AlicomFusionTemplateId_100001] ||
                        [scene isEqualToString:AlicomFusionTemplateId_100003];
  if (!token.length || !scheme.length || !supportedScene || !appName.length || !termsTitle.length ||
      !privacyTitle.length || [termsTitle isEqualToString:privacyTitle] ||
      !AFValidAgreementURL(termsURL) || !AFValidAgreementURL(privacyURL) ||
      (args[@"alternateLoginLabel"] && !alternateLoginLabel.length) ||
      (args[@"phoneInputLabel"] && !phoneInputLabel.length) ||
      (args[@"emailLoginLabel"] && !emailLoginLabel.length) ||
      ([args[@"appSms"] isEqual:@YES] && ![scene isEqual:AlicomFusionTemplateId_100001] &&
       ![scene isEqual:AlicomFusionTemplateId_100003]) ||
      ([args[@"startWithSms"] isEqual:@YES] && ![args[@"appSms"] isEqual:@YES]) ||
      (args[@"retainNumberPage"] &&
       (![args[@"retainNumberPage"] isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)args[@"retainNumberPage"]) != CFBooleanGetTypeID() ||
        ([args[@"retainNumberPage"] boolValue] &&
         ![scene isEqual:AlicomFusionTemplateId_100001]))) ||
      (loginCard && !AFValidLoginCard(loginCard)) ||
      ((phoneInputLabel || emailLoginLabel || loginCard) &&
       ![scene isEqualToString:AlicomFusionTemplateId_100001]) ||
      ([scene isEqualToString:AlicomFusionTemplateId_100003] && !phone.length)) {
    result([FlutterError errorWithCode:@"invalid_arguments"
                               message:@"认证参数不完整、协议链接无效或场景不支持"
                               details:nil]);
    return;
  }
  UIViewController *presenter = AFTopController(self.registrar.viewController);
  if (!presenter.view.window || presenter.isBeingDismissed) {
    result([FlutterError errorWithCode:@"no_view_controller"
                               message:@"当前没有可显示认证窗口的页面"
                               details:nil]);
    return;
  }
  if (![AFSDKCleanup isSupported]) {
    result([FlutterError errorWithCode:@"unsupported_sdk_version"
                               message:@"内置融合认证SDK版本不支持安全清理，请使用插件附带的SDK"
                               details:nil]);
    return;
  }
  AFFusionSession *session = [[AFFusionSession alloc] init];
  session.sceneId = scene;
  session.phoneNumber = phone;
  session.appName = appName;
  session.termsTitle = termsTitle;
  session.termsURL = termsURL;
  session.privacyTitle = privacyTitle;
  session.privacyURL = privacyURL;
  session.alternateLoginLabel = alternateLoginLabel;
  session.phoneInputLabel = phoneInputLabel;
  session.emailLoginLabel = emailLoginLabel;
  session.loginCard = loginCard;
  session.retainNumberPage = [args[@"retainNumberPage"] isEqual:@YES];
  BOOL appSmsRequested = [args[@"appSms"] isEqual:@YES];
  BOOL appSmsScene = [scene isEqual:AlicomFusionTemplateId_100001];
  if (!appSmsScene) {
    appSmsScene = [scene isEqual:AlicomFusionTemplateId_100003];
  }
  session.appSms = appSmsRequested && appSmsScene;
  session.startWithSms = session.appSms && [args[@"startWithSms"] isEqual:@YES];
  session.presenter = presenter;
  __weak AliyunFusionAuthPlugin *weakSelf = self;
  NSString *stageRequestId = AFRequiredString(args[@"stageRequestId"]);
  if (stageRequestId) {
    session.stageChanged = ^(NSString *stage, dispatch_block_t completion) {
      FlutterMethodChannel *channel = weakSelf.channel;
      if (!channel) {
        if (completion)
          completion();
        return;
      }
      [channel invokeMethod:@"authStageChanged"
                  arguments:@{@"requestId" : stageRequestId, @"stage" : stage}
                     result:^(id reply) {
                       if (completion)
                         dispatch_async(dispatch_get_main_queue(), completion);
                     }];
    };
  }
  session.completion = ^(id value) {
    result(value);
  };
  session.cleanupDidFinish = ^{
    weakSelf.session = nil;
  };
  self.session = session;
  AFActiveSession = session;
  [session startWithToken:token schemeCode:scheme];
}

- (void)detachFromEngineForRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  if (![NSThread isMainThread]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self detachFromEngineForRegistrar:registrar];
    });
    return;
  }
  [self.channel setMethodCallHandler:nil];
  [self.session finish:[FlutterError errorWithCode:@"cancelled"
                                           message:@"认证页面已关闭"
                                           details:nil]];
  self.registrar = nil;
}
@end
