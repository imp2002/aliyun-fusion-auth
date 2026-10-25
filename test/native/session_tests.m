// Runs against the supplied vendor and Flutter frameworks in an iOS Simulator.
// No FlutterEngine, auth delegate, valid token, network authentication or SMS.
#import "../../ios/Classes/AliyunFusionAuthPlugin.m"

static NSUInteger checks;
static void TestPhoneInput(NSUInteger mode);
static void TestConsentGate(void);
static void TestAppSms(void);
static void TestStageEvents(void);
static void TestRetainedNumberPage(void);
static void Check(BOOL condition, NSString *message) {
  checks++;
  if (!condition) {
    NSLog(@"FAIL: %@", message);
    exit(1);
  }
}

@interface AFTestCleanup : AFSDKCleanup
@property (nonatomic) NSUInteger calls;
@property (nonatomic, copy) dispatch_block_t pending;
@end
@implementation AFTestCleanup
- (void)destroyWithCompletion:(dispatch_block_t)completion {
  self.calls++;
  self.pending = completion;
}
@end

@interface AFTestHandler : NSObject
@property (nonatomic) NSUInteger stops;
@property (nonatomic) NSUInteger privacyCloses;
@property (nonatomic) NSUInteger continuations;
- (void)closeNumberAuthPrivactAlertView;
- (void)stopSceneWithTemplateId:(NSString *)sceneId;
- (void)continueSceneWithTemplateId:(NSString *)sceneId isSuccess:(BOOL)success;
@end
@implementation AFTestHandler
- (void)closeNumberAuthPrivactAlertView {
  Check(NSThread.isMainThread, @"Alternative login closes privacy UI on main");
  self.privacyCloses++;
}
- (void)stopSceneWithTemplateId:(NSString *)sceneId {
  Check([sceneId isEqual:AlicomFusionTemplateId_100001], @"Alternative login stops its scene");
  self.stops++;
}
- (void)continueSceneWithTemplateId:(NSString *)sceneId isSuccess:(BOOL)success {
  Check(NSThread.isMainThread && [sceneId isEqual:AlicomFusionTemplateId_100001] && !success,
        @"Carrier failure continues the configured fusion scene on main");
  self.continuations++;
}
@end

@interface AFTestNumberAuthModel : AlicomFusionNumberAuthModel
@property (nonatomic) NSUInteger phoneSwitches;
@end
@implementation AFTestNumberAuthModel
- (void)otherPhoneLogin {
  self.phoneSwitches++;
}
@end

// The callback only styles these public controls. Avoid constructing an SDK
// view, which would initialize its real SMS network and scene dependencies.
@interface AFTestVerifyCodeView : UIView
@property (nonatomic, copy) NSString *titleString;
@property (nonatomic, strong) UIButton *checkBoxBtn;
@property (nonatomic, strong) UITextField *phoneTextField;
@property (nonatomic, strong) UITextView *privacyTextView;
@property (nonatomic) NSUInteger sends;
@property (nonatomic) NSUInteger submits;
@property (nonatomic, copy) NSString *lastCode;
- (void)verifyCodeBtnClick:(NSString *)phone checked:(BOOL)checked;
- (void)submitVerifyCodeBtnClick:(NSString *)phone code:(NSString *)code;
@end
@implementation AFTestVerifyCodeView
- (void)verifyCodeBtnClick:(NSString *)phone checked:(BOOL)checked {
  Check(checked && self.checkBoxBtn.selected, @"Only consented SMS sends reach SDK");
  self.sends++;
}
- (void)submitVerifyCodeBtnClick:(NSString *)phone code:(NSString *)code {
  self.submits++;
  self.lastCode = code;
}
@end

@interface AFTestPromptSession : AFFusionSession
@property (nonatomic, copy) NSString *lastMessage;
@end
@implementation AFTestPromptSession
- (void)showMessage:(NSString *)message {
  self.lastMessage = message;
}
@end

static void TestAlternativeLogin(void) {
  AliyunFusionAuthPlugin *plugin = [AliyunFusionAuthPlugin new];
  for (id invalidLabel in @[ @17, @"  ", NSNull.null ]) {
    NSDictionary *arguments = @{
      @"authToken" : @"test-token",
      @"schemeCode" : @"test-scheme",
      @"sceneId" : AlicomFusionTemplateId_100001,
      @"appName" : @"Test App",
      @"termsTitle" : @"Terms",
      @"termsUrl" : @"https://example.com/terms",
      @"privacyTitle" : @"Privacy",
      @"privacyUrl" : @"https://example.com/privacy",
      @"privacyAccepted" : @YES,
      @"alternateLoginLabel" : invalidLabel
    };
    __block BOOL rejected = NO;
    [plugin handleMethodCall:[FlutterMethodCall methodCallWithMethodName:@"authenticate"
                                                               arguments:arguments]
                      result:^(id value) {
                        rejected = [value isKindOfClass:FlutterError.class] &&
                                   [((FlutterError *)value).code isEqual:@"invalid_arguments"];
                      }];
    Check(rejected, @"Invalid alternate labels are rejected before SDK initialization");
  }
  for (NSNumber *deferred in @[ @NO, @YES ]) {
    for (NSString *scene in @[ AlicomFusionTemplateId_100001, AlicomFusionTemplateId_100003 ]) {
      NSDictionary *args = @{
        @"authToken" : @"test-token",
        @"schemeCode" : @"test-scheme",
        @"sceneId" : scene,
        @"phoneNumber" : @"13800138000",
        @"appName" : @"Test",
        @"termsTitle" : @"Terms",
        @"termsUrl" : @"https://example.com/terms",
        @"privacyTitle" : @"Privacy",
        @"privacyUrl" : @"https://example.com/privacy",
        @"privacyAccepted" : @NO,
        @"deferConsentToNative" : deferred
      };
      __block NSString *code = nil;
      [plugin handleMethodCall:[FlutterMethodCall methodCallWithMethodName:@"authenticate"
                                                                 arguments:args]
                        result:^(id value) {
                          code = [(FlutterError *)value code];
                        }];
      BOOL loginPrefetch = deferred.boolValue && [scene isEqual:AlicomFusionTemplateId_100001];
      Check([code isEqual:loginPrefetch ? @"no_view_controller" : @"privacy_not_accepted"],
            @"Only explicitly deferred login can pass the pre-UI consent gate");
    }
  }
  AFFusionSession *session = [AFFusionSession new];
  AFTestHandler *testHandler = [AFTestHandler new];
  AlicomFusionAuthHandler *handler = (AlicomFusionAuthHandler *)testHandler;
  AFTestCleanup *cleanup = [AFTestCleanup new];
  session.handler = handler;
  session.cleanup = cleanup;
  session.sceneId = AlicomFusionTemplateId_100001;
  session.appName = @"Test App";
  session.termsTitle = @"Terms";
  session.termsURL = @"https://example.com/terms";
  session.privacyTitle = @"Privacy";
  session.privacyURL = @"https://example.com/privacy";

  AlicomFusionNumberAuthModel *defaultModel = [AlicomFusionNumberAuthModel new];
  defaultModel.changeBtnTitle = [[NSAttributedString alloc] initWithString:@"SDK default"];
  defaultModel.changeBtnIsHidden = YES;
  __block NSUInteger defaultActions = 0;
  defaultModel.moreLoginActionBlock = ^{
    defaultActions++;
  };
  [session onPhoneNumberVerifyUICustomDefined:handler
                                   templateId:session.sceneId
                                       nodeId:@"number"
                                      UIModel:defaultModel];
  Check([defaultModel.changeBtnTitle.string isEqual:@"SDK default"] &&
            defaultModel.changeBtnIsHidden,
        @"Omitted alternate label preserves the SDK's existing button");
  defaultModel.moreLoginActionBlock();
  Check(defaultActions == 1, @"Omitted alternate label preserves the SDK's action");
  CGRect fullPageNumber = defaultModel.numberFrameBlock(CGSizeMake(390, 844), CGSizeMake(390, 844),
                                                        CGRectMake(0, 150, 180, 36));
  Check(defaultModel.sloganIsHidden &&
            [defaultModel.loginBtnText.string isEqual:@"本机号码一键登录"] &&
            CGRectGetMidX(fullPageNumber) == 195 && fullPageNumber.size.width == 180,
        @"Full-page fallback also centers the number and hides the service slogan");

  session.alternateLoginLabel = @"密码登录";
  AFTestNumberAuthModel *model = [AFTestNumberAuthModel new];
  [session onPhoneNumberVerifyUICustomDefined:handler
                                   templateId:session.sceneId
                                       nodeId:@"number"
                                      UIModel:model];
  Check([model.changeBtnTitle.string isEqual:@"密码登录"] && !model.changeBtnIsHidden,
        @"Configured alternate login is visible with its requested label");
  Check(!model.checkBoxIsChecked && !model.checkBoxIsHidden && model.privacyOne.count == 2 &&
            model.privacyTwo.count == 2,
        @"Alternate login retains explicit operator consent and application agreements");
  Check(model.privacyFont.pointSize == 13 && [model.privacyPreText isEqual:@"我已阅读并同意"] &&
            [model.privacyOne[0] isEqual:AFProtocolTitle(session.termsTitle)] &&
            [model.privacyTwo[0] isEqual:AFProtocolTitle(session.privacyTitle)] &&
            [model.privacyOne[1] isEqual:session.termsURL] &&
            [model.privacyTwo[1] isEqual:session.privacyURL] &&
            [model.privacyOperatorPreText isEqual:@"《"] &&
            [model.privacyOperatorSufText isEqual:@"》"],
        @"Native agreement uses one smaller font and book-title marks, preserving all URLs");
  Check([AFProtocolTitle(@"《用户协议》") isEqual:@"《用户协议》"],
        @"Already bracketed protocol titles are not wrapped twice");

  session.started = YES;
  AFActiveSession = session;
  __block NSUInteger replies = 0;
  __weak AFFusionSession *weakSession = session;
  session.completion = ^(id value) {
    replies++;
    Check([value isKindOfClass:FlutterError.class] &&
              [((FlutterError *)value).code isEqual:@"alternative_login"],
          @"Alternative login completes with a distinct navigation outcome");
    Check(weakSession.cleanupComplete,
          @"Dart receives alternative login only after native cleanup");
  };
  dispatch_block_t chooseAlternative = model.moreLoginActionBlock;
  chooseAlternative();
  chooseAlternative();
  [session onVerifySuccess:handler
                  nodeName:@"number"
                 maskToken:@"late-proof"
                     event:[AlicomFusionEvent new]];
  Check(!session.finished && cleanup.calls == 0 && replies == 0 && AFActiveSession == session,
        @"Alternative login defers cleanup until the SDK callback has returned");
  dispatch_async(dispatch_get_main_queue(), ^{
    Check(session.finished && replies == 0 && cleanup.calls == 1 && testHandler.stops == 1 &&
              testHandler.privacyCloses == 1 && AFActiveSession == session,
          @"Repeated taps and late verification success cannot interrupt alternate navigation");
    dispatch_block_t complete = cleanup.pending;
    cleanup.pending = nil;
    complete();
    Check(replies == 1 && session.cleanupComplete && AFActiveSession == nil,
          @"Alternative login releases native ownership before returning to Flutter");
    chooseAlternative();
    [session onVerifySuccess:handler
                    nodeName:@"number"
                   maskToken:@"later-proof"
                       event:[AlicomFusionEvent new]];
    dispatch_async(dispatch_get_main_queue(), ^{
      Check(replies == 1 && cleanup.calls == 1,
            @"Callbacks after alternative login cannot deliver a verification proof");
      TestPhoneInput(0);
    });
  });
}

static void TestPhoneInput(NSUInteger mode) {
  AFTestPromptSession *session = [AFTestPromptSession new];
  AFTestHandler *testHandler = [AFTestHandler new];
  AlicomFusionAuthHandler *handler = (AlicomFusionAuthHandler *)testHandler;
  AFTestCleanup *cleanup = [AFTestCleanup new];
  session.handler = handler;
  session.cleanup = cleanup;
  session.sceneId = AlicomFusionTemplateId_100001;
  session.appName = @"Test";
  session.termsTitle = @"Terms";
  session.termsURL = @"https://example.com/terms";
  session.privacyTitle = @"Privacy";
  session.privacyURL = @"https://example.com/privacy";
  session.phoneInputLabel = @"换号";
  session.emailLoginLabel = @"邮箱验证码登录";
  session.alternateLoginLabel = @"密码登录";
  session.loginCard = @{
    @"x" : @30,
    @"y" : @160,
    @"width" : @330,
    @"height" : @440,
    @"textScale" : @1,
    @"backgroundColor" : @0xFFFFFFFF,
    @"primaryColor" : @0xFF0092FF,
    @"textColor" : @0xFF111111,
    @"secondaryTextColor" : @0xFF777777,
    @"title" : @"本机号码一键登录"
  };
  Check(AFValidLoginCard(session.loginCard), @"Valid card configuration accepted");
  NSMutableDictionary *invalid = [session.loginCard mutableCopy];
  invalid[@"width"] = @YES;
  Check(!AFValidLoginCard(invalid), @"Boolean geometry is rejected");
  invalid[@"width"] = @100;
  Check(!AFValidLoginCard(invalid), @"Unreadably narrow card is rejected");
  AFTestNumberAuthModel *model = [AFTestNumberAuthModel new];
  [session onPhoneNumberVerifyUICustomDefined:handler
                                   templateId:session.sceneId
                                       nodeId:@"number"
                                      UIModel:model];
  Check([model.otherLoginButton.currentTitle isEqual:@"换号"],
        @"Change number has a distinct action");
  Check(model.nameLabel.hidden && model.sloganIsHidden &&
            [model.loginBtnText.string isEqual:@"本机号码一键登录"] &&
            [session.loginCardControls.consentPromptButton.accessibilityLabel
                isEqual:model.loginBtnText.string],
        @"Card presents one login title in the button without extra heading or vendor slogan");
  Check(!model.checkBoxIsHidden && !model.checkBoxIsChecked && model.privacyOne.count == 2 &&
            model.privacyTwo.count == 2,
        @"Card retains unchecked consent and application agreements");
  CGSize size = CGSizeMake(330, 440);
  CGRect number = model.numberFrameBlock(size, size, CGRectMake(0, 0, 160, 34));
  CGRect change = model.otherLoginButtonFrameBlock(size, size, CGRectZero);
  Check(CGRectGetMinX(change) > CGRectGetMaxX(number) &&
            fabs(CGRectGetMidY(number) - CGRectGetMidY(change)) < 20 &&
            fabs(CGRectGetMidX(number) - size.width / 2) < 0.01,
        @"Masked number is centered in the card with the change action to its right");
  CGRect content =
      model.contentViewFrameBlock(CGSizeMake(390, 844), CGSizeMake(390, 844), CGRectZero);
  Check(CGRectEqualToRect(content, CGRectMake(30, 160, 330, 440)),
        @"Native card uses the supplied Flutter region");
  CGRect login = model.loginBtnFrameBlock(size, size, CGRectZero);
  CGRect alternate = model.changeBtnFrameBlock(size, size, CGRectZero);
  CGRect privacy = model.privacyFrameBlock(size, size, CGRectZero);
  UIView *parent = [[UIView alloc] initWithFrame:(CGRect){CGPointZero, size}];
  model.customViewBlock(parent);
  model.customViewLayoutBlock(size, content, CGRectZero, CGRectZero, CGRectZero, CGRectZero,
                              CGRectZero, CGRectZero, number, login, alternate, privacy);
  Check(CGRectGetMinX(session.loginCardControls.emailButton.frame) > CGRectGetMaxX(alternate),
        @"Email verification sits beside password login");
  UIButton *email = session.loginCardControls.emailButton;
  Check([email.currentTitle sizeWithAttributes:@{NSFontAttributeName : email.titleLabel.font}]
                .width <= email.frame.size.width,
        @"Email verification label fits without truncation");
  Check(CGRectGetMinY(privacy) > CGRectGetMaxY(alternate),
        @"Agreements are below the login actions");
  Check([[session.loginCardControls.emailButton actionsForTarget:session
                                                 forControlEvent:UIControlEventTouchUpInside]
            containsObject:@"chooseEmailLogin"],
        @"Email button has its own navigation outcome");
  Check([parent hitTest:CGPointMake(CGRectGetMidX(login), CGRectGetMidY(login))
              withEvent:nil] == session.loginCardControls.consentPromptButton,
        @"Unchecked consent routes taps to the reminder instead of SDK authorization");
  Check(
      [[session.loginCardControls.consentPromptButton actionsForTarget:session
                                                       forControlEvent:UIControlEventTouchUpInside]
          containsObject:@"promptForCarrierConsent"],
      @"Unchecked login button targets the consent reminder");
  // This command-line harness has no UIApplication event dispatcher.
  [session promptForCarrierConsent];
  Check([session.lastMessage isEqualToString:@"请先阅读并勾选同意下方协议"] && !session.finished &&
            !model.checkBoxIsChecked && testHandler.stops == 0,
        @"Tapping unchecked login only reminds without granting consent or finishing auth");
  Check(model.privacyAlignment == NSTextAlignmentLeft &&
            CGRectGetMinX(privacy) == CGRectGetMinX(login) &&
            model.privacyFont.pointSize == 13 * [session.loginCard[@"textScale"] doubleValue] &&
            (model.privacyFont.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold),
        @"Carrier agreement stays aligned and uniformly scales its smaller bold font");
  session.started = YES;
  AFActiveSession = session;
  __block NSUInteger replies = 0;
  session.completion = ^(id result) {
    replies++;
    if (mode == 2) {
      Check([result isKindOfClass:FlutterError.class] &&
                [((FlutterError *)result).code isEqual:@"email_login"],
            @"Email switch returns its own navigation outcome");
    } else {
      Check([result isKindOfClass:NSDictionary.class] &&
                [result[@"verifyToken"] isEqual:@"sms-proof"],
            @"Fusion SMS returns a proof for backend verification");
    }
  };
  if (mode == 1) {
    [session onVerifyFailed:handler nodeName:@"number" error:[AlicomFusionEvent new]];
  } else if (mode == 0) {
    Check([[model.otherLoginButton actionsForTarget:model
                                    forControlEvent:UIControlEventTouchUpInside]
              containsObject:@"otherPhoneLogin"],
          @"Change button targets the public SDK phone-switch action");
    // This command-line simulator test has no UIApplication event dispatcher.
    [model otherPhoneLogin];
    Check(model.phoneSwitches == 1 && !session.finished && !session.inputRequested &&
              testHandler.stops == 0,
          @"Changing numbers leaves the fusion session active");
  } else {
    [session chooseEmailLogin];
    [session chooseEmailLogin];
    [session onVerifySuccess:handler
                    nodeName:@"number"
                   maskToken:@"late-proof"
                       event:[AlicomFusionEvent new]];
  }
  Check(replies == 0 && cleanup.calls == 0, @"Navigation waits for deferred cleanup");
  dispatch_async(dispatch_get_main_queue(), ^{
    if (mode != 2) {
      Check(testHandler.continuations == (mode == 1 ? 1 : 0) && !session.finished &&
                !session.inputRequested && cleanup.calls == 0 && replies == 0,
            @"Number switch or carrier fallback retains its live fusion session");
      AFTestVerifyCodeView *sms = [AFTestVerifyCodeView new];
      sms.checkBoxBtn = [UIButton buttonWithType:UIButtonTypeCustom];
      sms.checkBoxBtn.selected = YES;
      sms.phoneTextField = [UITextField new];
      sms.privacyTextView = [UITextView new];
      sms.privacyTextView.attributedText =
          [[NSAttributedString alloc] initWithString:@"SDK carrier agreement"];
      [session onSMSCodeVerifyUICustomDefined:handler
                                   templateId:session.sceneId
                                       nodeId:@"sms"
                                  isAutoInput:NO
                                         view:(AlicomFusionVerifyCodeView *)sms];
      Check(
          !session.finished && !session.inputRequested && cleanup.calls == 0 &&
              [sms.titleString isEqual:@"Test手机验证"] && !sms.checkBoxBtn.selected &&
              [sms.privacyTextView.attributedText.string containsString:@"SDK carrier agreement"] &&
              [sms.privacyTextView.attributedText.string containsString:@"Terms"] &&
              [sms.privacyTextView.attributedText.string containsString:@"Privacy"],
          @"SMS stays in the SDK and retains its agreements with explicit consent");
      [session onVerifyFailed:handler
                     nodeName:AlicomFusionNodeNameVerifyCodeAuth
                        error:[AlicomFusionEvent new]];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      if (mode != 2) {
        Check(!session.finished && cleanup.calls == 0 && replies == 0 &&
                  testHandler.continuations == (mode == 1 ? 1 : 0) &&
                  [session.lastMessage isEqual:@"验证码校验失败，请检查后重试"],
              @"Incorrect SMS codes remain recoverable without terminating or advancing the scene");
        [session onVerifySuccess:handler
                        nodeName:AlicomFusionNodeNameVerifyCodeAuth
                       maskToken:@"sms-proof"
                           event:[AlicomFusionEvent new]];
      }
      dispatch_async(dispatch_get_main_queue(), ^{
        Check(cleanup.calls == 1 && replies == 0, @"One cleanup owns the completed flow");
        cleanup.pending();
        cleanup.pending = nil;
        Check(replies == 1 && AFActiveSession == nil,
              @"Completion returns to Flutter only after native ownership release");
        if (mode < 2) {
          TestPhoneInput(mode + 1);
        } else {
          TestConsentGate();
        }
      });
    });
  });
}

@interface AFTestConsentEvent : AlicomFusionEvent
@property (nonatomic, strong) id selected;
@end
@implementation AFTestConsentEvent
- (NSString *)resultCode {
  return AlicomFusionNumberAuthGetTokenEvent;
}
- (NSString *)innerCode {
  return AlicomFusionNumberAuthCodeLoginControllerClickCheckBoxBtn;
}
- (NSDictionary *)extendData {
  return self.selected ? @{@"isCheckBoxSelected" : self.selected} : @{};
}
@end

static void CheckConsentValue(AFFusionSession *session, NSArray *values, NSUInteger index) {
  if (index == values.count) {
    TestStageEvents();
    return;
  }
  id value = values[index];
  AFTestConsentEvent *event = [AFTestConsentEvent new];
  event.selected = value == NSNull.null ? nil : value;
  BOOL expected = [value isEqual:@1] || [value isEqual:@"1"];
  [session onAuthEvent:session.handler eventData:event];
  dispatch_async(dispatch_get_main_queue(), ^{
    Check(session.loginCardControls.consentPromptButton.hidden == expected,
          @"SDK checkbox events switch reminder/SDK login; malformed consent keeps reminder");
    CheckConsentValue(session, values, index + 1);
  });
}

static void TestConsentGate(void) {
  AFFusionSession *session = [AFFusionSession new];
  session.handler = (AlicomFusionAuthHandler *)[AFTestHandler new];
  session.loginCardControls = [AFLoginCardControls new];
  Check(session.loginCardControls.consentPromptButton.enabled &&
            !session.loginCardControls.consentPromptButton.hidden,
        @"Carrier login shows a tappable consent reminder until explicit consent");
  CheckConsentValue(session, @[ @1, @0, @"1", @"0", @"true", NSNull.null ], 0);
}

static void TestSession(void) {
  AliyunFusionAuthPlugin *firstEngine = [AliyunFusionAuthPlugin new];
  AliyunFusionAuthPlugin *secondEngine = [AliyunFusionAuthPlugin new];
  AFFusionSession *session = [AFFusionSession new];
  AFTestCleanup *cleanup = [AFTestCleanup new];
  session.cleanup = cleanup;
  firstEngine.session = session;
  AFActiveSession = session;
  __block NSUInteger authReplies = 0;
  __block NSUInteger cancelReplies = 0;
  __block NSUInteger cleanupReplies = 0;
  session.completion = ^(id value) {
    authReplies++;
    Check([value isEqual:@"first-result"], @"First terminal result wins");
  };
  session.cleanupDidFinish = ^{
    cleanupReplies++;
  };
  [session finish:@"first-result"];
  [session finish:@"ignored-result"];
  Check(cleanup.calls == 1, @"Repeated finish starts teardown once");
  [secondEngine handleMethodCall:[FlutterMethodCall methodCallWithMethodName:@"authenticate"
                                                                   arguments:nil]
                          result:^(id value) {
                            Check([value isKindOfClass:FlutterError.class] &&
                                      [((FlutterError *)value).code isEqual:@"busy"],
                                  @"Other FlutterEngine blocked during cleanup");
                          }];
  for (NSUInteger i = 0; i < 2; i++) {
    [firstEngine
        handleMethodCall:[FlutterMethodCall methodCallWithMethodName:@"cancel" arguments:nil]
                  result:^(id value) {
                    cancelReplies++;
                    Check(value == nil, @"Cancel completes successfully only after teardown");
                  }];
  }
  Check(authReplies == 0 && cancelReplies == 0, @"Flutter results wait for teardown");
  Check(AFActiveSession == session, @"Process ownership retained while SDK pending");
  dispatch_block_t complete = cleanup.pending;
  cleanup.pending = nil;
  complete();
  Check(authReplies == 1 && cancelReplies == 2 && cleanupReplies == 1,
        @"All waiting Flutter calls complete once");
  Check(AFActiveSession == nil && session.cleanupComplete,
        @"Process ownership released after SDK/UI cleanup");
  [session finish:@"ignored-late-result"];
  [session cancelWithReply:^(id value) {
    Check(value == nil, @"Cancel after completion is idempotent");
    cancelReplies++;
  }];
  Check(authReplies == 1 && cancelReplies == 3 && cleanup.calls == 1,
        @"Late finish cannot deliver another result");
  TestAlternativeLogin();
}

// Model an already-presented navigation controller without launching UIApplication.
@interface AFTestStageEvent : AlicomFusionEvent
@property (nonatomic, copy) NSString *testCode;
@end
@implementation AFTestStageEvent
- (NSString *)resultCode {
  return self.testCode;
}
@end

static void TestStageEvents(void) {
  AFFusionSession *session = [AFFusionSession new];
  session.handler = (AlicomFusionAuthHandler *)[AFTestHandler new];
  session.appSms = YES;
  NSMutableArray *stages = [NSMutableArray array];
  session.stageChanged = ^(NSString *stage, dispatch_block_t completion) {
    Check(NSThread.isMainThread, @"UI stages are delivered on the main queue");
    [stages addObject:stage];
    if (completion)
      completion();
  };
  AFTestStageEvent *ready = [AFTestStageEvent new];
  ready.testCode = AlicomFusionNumberAuthPresentSuccess;
  AFTestStageEvent *switching = [AFTestStageEvent new];
  switching.testCode = AlicomFusionNumberAuthOtherPhoneLoginClickEvent;
  [session onAuthEvent:session.handler eventData:ready];
  [session onAuthEvent:session.handler eventData:switching];
  [session onAuthEvent:(AlicomFusionAuthHandler *)[AFTestHandler new] eventData:ready];
  dispatch_async(dispatch_get_main_queue(), ^{
    Check([stages isEqual:@[ @"numberReady", @"smsSwitching" ]],
          @"Presentation and phone-switch events are distinct; foreign callbacks ignored");
    Check(!session.finished && !session.smsReady,
          @"UI progress never completes auth or claims SMS is ready");
    session.finished = YES;
    [session onAuthEvent:session.handler eventData:ready];
    dispatch_async(dispatch_get_main_queue(), ^{
      Check(stages.count == 2, @"Finished sessions cannot send late UI stages");
      TestRetainedNumberPage();
    });
  });
}

@interface AFTestLoginClickEvent : AlicomFusionEvent
@end
@implementation AFTestLoginClickEvent
- (NSString *)resultCode {
  return AlicomFusionNumberAuthGetTokenEvent;
}
- (NSString *)innerCode {
  return AlicomFusionNumberAuthCodeLoginControllerClickLoginBtn;
}
@end

// Visible hierarchy evidence without launching an application or SDK scene.
@interface AFTestSnapshotView : UIView
@property (nonatomic, strong) UIWindow *visibleWindow;
@end
@implementation AFTestSnapshotView
- (UIWindow *)window {
  return self.visibleWindow;
}
@end

static void TestRetainedNumberPage(void) {
  AFFusionSession *session = [AFFusionSession new];
  AFTestHandler *handler = [AFTestHandler new];
  AFTestCleanup *cleanup = [AFTestCleanup new];
  session.handler = (AlicomFusionAuthHandler *)handler;
  session.cleanup = cleanup;
  session.sceneId = AlicomFusionTemplateId_100001;
  session.started = YES;
  session.retainNumberPage = YES;
  AFActiveSession = session;
  AlicomFusionNumberAuthModel *model = [AlicomFusionNumberAuthModel new];
  UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
  AFTestSnapshotView *root = [[AFTestSnapshotView alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
  root.visibleWindow = window;
  UIViewController *presenter = [UIViewController new];
  presenter.view = root;
  session.presenter = presenter;
  AFTestSnapshotView *parent =
      [[AFTestSnapshotView alloc] initWithFrame:CGRectMake(30, 200, 330, 400)];
  parent.visibleWindow = window;
  parent.backgroundColor = UIColor.whiteColor;
  [root addSubview:parent];
  UIView *numberAndAgreements = [UIView new];
  model.customViewBlock = ^(UIView *view) {
    [view addSubview:numberAndAgreements];
  };
  session.numberPageLoading = AFConfigureNumberPageLoading(model);
  model.customViewBlock(parent);
  CGRect login = CGRectMake(0, 80, 330, 50);
  model.customViewLayoutBlock(CGSizeMake(390, 844), parent.frame, CGRectZero, CGRectZero,
                              CGRectZero, CGRectZero, CGRectZero, CGRectZero, CGRectZero, login,
                              CGRectZero, CGRectZero);
  UIView *shield = parent.subviews.lastObject;
  Check(shield.hidden && numberAndAgreements.superview == parent,
        @"Loading customization preserves the SDK's existing number and agreements");
  [session snapshotNumberPageWithReply:^(id value) {
    Check([value isKindOfClass:FlutterError.class], @"No snapshot is available before proof");
  }];
  __block dispatch_block_t painted;
  __block NSUInteger proofs = 0;
  session.stageChanged = ^(NSString *stage, dispatch_block_t completion) {
    Check([stage isEqual:@"authorizing"], @"Consented login publishes authorizing stage");
    painted = completion;
  };
  session.completion = ^(id value) {
    Check([value[@"verifyToken"] isEqual:@"proof"] && [value[@"numberPageRetained"] isEqual:@YES],
          @"Retained proof tells Dart it still owns the native page");
    proofs++;
  };
  [session onAuthEvent:session.handler eventData:[AFTestLoginClickEvent new]];
  dispatch_async(dispatch_get_main_queue(), ^{
    Check(shield.hidden && !session.numberPageRetained,
          @"Unchecked login never starts loading or grants consent");
    session.carrierConsent = YES;
    [session onAuthEvent:session.handler eventData:[AFTestLoginClickEvent new]];
    dispatch_async(dispatch_get_main_queue(), ^{
      Check(!shield.hidden && shield.accessibilityViewIsModal &&
                CGRectEqualToRect(shield.subviews.firstObject.frame, login),
            @"Consented login shields duplicate actions and loads inside the original button");
      [session onVerifySuccess:session.handler
                      nodeName:AlicomFusionNodeNameNumberAuth
                     maskToken:@"proof"
                         event:[AlicomFusionEvent new]];
      [session onVerifySuccess:session.handler
                      nodeName:AlicomFusionNodeNameNumberAuth
                     maskToken:@"duplicate"
                         event:[AlicomFusionEvent new]];
      [session onVerifySuccess:session.handler
                      nodeName:AlicomFusionNodeNameNumberAuth
                     maskToken:@""
                         event:[AlicomFusionEvent new]];
      [session onSDKTokenAuthFailure:session.handler
                           failToken:session.initialToken
                               error:[AlicomFusionEvent new]];
      [session onVerifyInterrupt:session.handler event:[AlicomFusionEvent new]];
      [session onTemplateFinish:session.handler event:[AlicomFusionEvent new]];
      dispatch_async(dispatch_get_main_queue(), ^{
        Check(proofs == 0 && painted != nil && cleanup.calls == 0 && !session.finished,
              @"Proof waits for app state; late SDK results/failures cannot dismiss the page");
        Check([session onSDKTokenUpdate:session.handler] == nil,
              @"Held proof needs no SDK token refresh during server exchange");
        painted();
        painted = nil;
        Check(proofs == 1 && handler.stops == 0 && AFActiveSession == session &&
                  numberAndAgreements.superview == parent,
              @"Server exchange keeps the same visible SDK page and process ownership");
        Check(session.presenter == presenter, @"Snapshot uses the presenting Flutter coordinates");
        [session snapshotNumberPageWithReply:^(id value) {
          FlutterStandardTypedData *png = value[@"png"];
          Check(png.data.length > 100 && [value[@"x"] doubleValue] == 30 &&
                    [value[@"y"] doubleValue] == 200 && [value[@"width"] doubleValue] == 330 &&
                    [value[@"height"] doubleValue] == 400 && cleanup.calls == 0,
                @"Snapshot returns an in-memory image and frame without closing the native page");
        }];
        __block NSUInteger cancellations = 0;
        [session cancelWithReply:^(id value) {
          Check(value == nil, @"Retained page cancellation completes after cleanup");
          cancellations++;
        }];
        Check(cleanup.calls == 1 && cancellations == 0 && shield.superview == parent &&
                  !shield.hidden,
              @"Loading and duplicate-action shield remain throughout native dismissal");
        [session snapshotNumberPageWithReply:^(id value) {
          Check([value isKindOfClass:FlutterError.class],
                @"Closing sessions cannot capture stale UI");
        }];
        dispatch_block_t done = cleanup.pending;
        cleanup.pending = nil;
        done();
        Check(session.cleanupComplete && session.numberPageLoading == nil &&
                  session.handler == nil && AFActiveSession == nil && cancellations == 1 &&
                  proofs == 1 && shield.superview == nil,
              @"Cleanup releases controls, handler and ownership without another proof");
        TestAppSms();
      });
    });
  });
}

@interface AFTestSmsNavigation : UINavigationController
@property (nonatomic, strong) UIViewController *testPresenter;
@end
@implementation AFTestSmsNavigation
- (UIViewController *)presentingViewController {
  return self.testPresenter;
}
- (void)dismissViewControllerAnimated:(BOOL)animated completion:(void (^)(void))completion {
  self.testPresenter = nil;
  if (completion)
    completion();
}
@end

@interface AFTestSmsEvent : AlicomFusionEvent
@end
@implementation AFTestSmsEvent
- (NSString *)resultCode {
  return AlicomFusionVerifyCodeGetSuccess;
}
@end

static void TestAppSms(void) {
  AFFusionSession *session = [AFFusionSession new];
  AFTestHandler *testHandler = [AFTestHandler new];
  session.handler = (AlicomFusionAuthHandler *)testHandler;
  session.cleanup = [AFTestCleanup new];
  session.sceneId = AlicomFusionTemplateId_100001;
  session.appSms = YES;
  session.started = YES;
  AFActiveSession = session;
  AFTestVerifyCodeView *sms = [AFTestVerifyCodeView new];
  sms.phoneTextField = [UITextField new];
  sms.checkBoxBtn = [UIButton new];
  AFTestSmsNavigation *navigation = [AFTestSmsNavigation new];
  navigation.testPresenter = [UIViewController new];
  session.sdkNavigation = navigation;
  __block NSUInteger handoffs = 0;
  session.completion = ^(id value) {
    Check([value isKindOfClass:FlutterError.class] &&
              [[(FlutterError *)value code] isEqual:@"app_sms_ready"],
          @"SMS hands presentation back with a session ID");
    handoffs++;
  };
  __block dispatch_block_t painted;
  session.stageChanged = ^(NSString *stage, dispatch_block_t completion) {
    Check([stage isEqual:@"smsSwitching"], @"SMS prepares the Flutter input form first");
    painted = completion;
  };
  [session onSMSCodeVerifyUICustomDefined:session.handler
                               templateId:session.sceneId
                                   nodeId:@"sms"
                              isAutoInput:NO
                                     view:(AlicomFusionVerifyCodeView *)sms];
  Check(painted != nil && !navigation.view.hidden && navigation.testPresenter != nil &&
            handoffs == 0 && !session.smsReady,
        @"UIKit handoff waits for Flutter to replace its loading placeholder");
  painted();
  painted = nil;
  dispatch_async(dispatch_get_main_queue(), ^{
    Check(handoffs == 1 && session.smsReady && !session.finished && testHandler.stops == 0,
          @"Handoff retains live SDK scene");
    Check(sms.sends == 0 && sms.submits == 0 && sms.hidden && !sms.checkBoxBtn.selected,
          @"Opening app SMS form never sends or grants consent");
    NSMutableDictionary *args = [@{
      @"sessionId" : session.smsSessionId,
      @"phone" : @"13800138000",
      @"privacyAccepted" : @NO
    } mutableCopy];
    [session handleSmsCommand:[FlutterMethodCall methodCallWithMethodName:@"sendSmsCode"
                                                                arguments:args]
                       result:^(id value) {
                         Check([[(FlutterError *)value code] isEqual:@"privacy_not_accepted"],
                               @"Native SMS rejects unchecked consent");
                       }];
    Check(sms.sends == 0, @"Rejected consent cannot invoke SDK sending");
    args[@"privacyAccepted"] = @YES;
    __block NSUInteger sendReplies = 0;
    [session handleSmsCommand:[FlutterMethodCall methodCallWithMethodName:@"sendSmsCode"
                                                                arguments:args]
                       result:^(id value) {
                         Check(value == nil, @"SDK successful send resolves app request");
                         sendReplies++;
                       }];
    Check(sms.sends == 1 && sendReplies == 0, @"Invoking SDK is not yet a successful send");
    [session onAuthEvent:session.handler eventData:[AFTestSmsEvent new]];
    dispatch_async(dispatch_get_main_queue(), ^{
      Check(sendReplies == 1 && [session.smsSentPhone isEqual:@"13800138000"],
            @"Send binds successful target");
      args[@"phone"] = @"13900139000";
      args[@"code"] = @"1234";
      [session handleSmsCommand:[FlutterMethodCall methodCallWithMethodName:@"submitSmsCode"
                                                                  arguments:args]
                         result:^(id value) {
                           Check([[(FlutterError *)value code] isEqual:@"invalid_arguments"],
                                 @"Cannot submit another phone's code");
                         }];
      args[@"phone"] = @"13800138000";
      __block NSUInteger proofs = 0;
      [session handleSmsCommand:[FlutterMethodCall methodCallWithMethodName:@"submitSmsCode"
                                                                  arguments:args]
                         result:^(id value) {
                           Check([value[@"verifyToken"] isEqual:@"first-proof"],
                                 @"Submit returns fusion proof");
                           proofs++;
                         }];
      [session onVerifySuccess:session.handler
                      nodeName:@"sms"
                     maskToken:@"first-proof"
                         event:[AlicomFusionEvent new]];
      dispatch_async(dispatch_get_main_queue(), ^{
        Check(proofs == 1 && sms.submits == 1 && !session.finished,
              @"Server can reject proof without losing SDK session");
        args[@"code"] = @"4321";
        [session handleSmsCommand:[FlutterMethodCall methodCallWithMethodName:@"submitSmsCode"
                                                                    arguments:args]
                           result:^(id value) {
                             Check([value[@"verifyToken"] isEqual:@"fresh-proof"],
                                   @"Retry uses a fresh fusion proof");
                             proofs++;
                           }];
        [session onVerifySuccess:session.handler
                        nodeName:@"sms"
                       maskToken:@"fresh-proof"
                           event:[AlicomFusionEvent new]];
        dispatch_async(dispatch_get_main_queue(), ^{
          Check(proofs == 2 && sms.submits == 2 && [sms.lastCode isEqual:@"4321"],
                @"Corrected code stays in the same SDK session");
          [session handleSmsCommand:[FlutterMethodCall methodCallWithMethodName:@"sendSmsCode"
                                                                      arguments:args]
                             result:^(id value) {
                               Check([[(FlutterError *)value code] isEqual:@"cancelled"],
                                     @"Cancellation drains pending SMS send");
                             }];
          [session cancelWithReply:^(id value) {
            Check(value == nil, @"SMS cancellation waits for cleanup");
          }];
          AFTestCleanup *cleanup = (AFTestCleanup *)session.cleanup;
          dispatch_block_t done = cleanup.pending;
          cleanup.pending = nil;
          done();
          Check(session.cleanupComplete && session.smsView == nil && handoffs == 1,
                @"Cleanup releases SMS view without replying to original authentication twice");
          NSLog(@"PASS: %lu native session/runtime assertions", (unsigned long)checks);
          exit(0);
        });
      });
    });
  });
}

int main(void) {
  @autoreleasepool {
    NSLog(@"Vendor runtime getSDKVersion = %@", [AlicomFusionAuthHandler getSDKVersion]);
    Check([[AlicomFusionAuthHandler getSDKVersion] isEqual:@"1.2.14"],
          @"Supplied archive runtime version confirmed");
    Check([AFSDKCleanup isSupported], @"Real vendor method signatures pass adapter guard");
    [AlicomFusionLog logEnable:NO];
    [AlicomFusionAuthHandler useSDKSupplyUMSDK:NO];
    // Construct only the local vendor graph, without setting the delegate that
    // starts authentication. This confirms synchronous instance initialization.
    AlicomFusionAuthToken *token = [[AlicomFusionAuthToken alloc] initWithTokenStr:@""];
    AlicomFusionAuthHandler *handler = [[AlicomFusionAuthHandler alloc] initWithToken:token
                                                                           schemeCode:@""];
    AFSDKCleanup *cleanup = [[AFSDKCleanup alloc] initWithHandler:handler];
    Check(cleanup != nil, @"Real constructor synchronously builds supported instance graph");
    [cleanup destroyWithCompletion:^{
      Check(NSThread.isMainThread, @"Real no-UI destroy completes on main");
      TestSession();
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(),
                   ^{
                     NSLog(@"FAIL: native test did not complete");
                     exit(2);
                   });
    CFRunLoopRun();
  }
}
