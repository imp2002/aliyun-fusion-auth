#import <AlicomFusionAuth/AlicomFusionAuth.h>

BOOL AFValidLoginCard(id value);

// Added through the SDK's public custom-view hooks. The SDK still owns its
// actual login button, carrier checkbox, agreements and authorization.
@interface AFLoginCardControls : NSObject
@property (nonatomic, strong, readonly) UIButton *consentPromptButton;
@property (nonatomic, strong, readonly) UIButton *emailButton;
- (void)setCarrierConsent:(BOOL)accepted;
@end

AFLoginCardControls *AFConfigureLoginCard(AlicomFusionNumberAuthModel *model, NSDictionary *card,
                                          NSString *emailLabel);

// A noninteractive loading button and input shield added through public hooks.
// It owns no SDK model, controller, callback or timer.
@interface AFNumberPageLoading : NSObject
@property (nonatomic, weak, readonly) UIView *contentView;
- (void)setAuthorizing:(BOOL)authorizing;
- (void)invalidate;
@end

AFNumberPageLoading *AFConfigureNumberPageLoading(AlicomFusionNumberAuthModel *model);
