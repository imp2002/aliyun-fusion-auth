#import "AFLoginCard.h"
#import <math.h>

@interface AFNumberPageLoading ()
@property (nonatomic, weak, readwrite) UIView *contentView;
@property (nonatomic, strong) UIView *shield;
@property (nonatomic, strong) UIImageView *button;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation AFNumberPageLoading
- (void)setAuthorizing:(BOOL)authorizing {
  self.shield.hidden = !authorizing;
  if (authorizing) {
    [self.shield.superview bringSubviewToFront:self.shield];
    [self.spinner startAnimating];
  } else {
    [self.spinner stopAnimating];
  }
}
- (void)invalidate {
  [self.spinner stopAnimating];
  [self.shield removeFromSuperview];
}
@end

AFNumberPageLoading *AFConfigureNumberPageLoading(AlicomFusionNumberAuthModel *model) {
  AFNumberPageLoading *loading = [AFNumberPageLoading new];
  loading.shield = [UIView new];
  loading.shield.hidden = YES;
  loading.shield.accessibilityViewIsModal = YES;
  loading.shield.isAccessibilityElement = YES;
  loading.shield.accessibilityLabel = @"登录中";
  loading.button = [[UIImageView alloc] initWithImage:model.loginBtnBgImgs.firstObject];
  loading.button.backgroundColor =
      loading.button.image ? UIColor.clearColor : UIColor.systemBlueColor;
  loading.button.layer.cornerRadius = 8;
  loading.button.clipsToBounds = YES;
  loading.spinner = [[UIActivityIndicatorView alloc]
      initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
  loading.spinner.color = UIColor.whiteColor;
  UILabel *label = [UILabel new];
  NSDictionary *attributes =
      model.loginBtnText.length ? [model.loginBtnText attributesAtIndex:0 effectiveRange:nil] : @{};
  label.font =
      attributes[NSFontAttributeName] ?: [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
  label.textColor = attributes[NSForegroundColorAttributeName] ?: UIColor.whiteColor;
  label.text = @"登录中";
  UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[ loading.spinner, label ]];
  content.spacing = 10;
  content.alignment = UIStackViewAlignmentCenter;
  content.translatesAutoresizingMaskIntoConstraints = NO;
  [loading.button addSubview:content];
  [NSLayoutConstraint activateConstraints:@[
    [content.centerXAnchor constraintEqualToAnchor:loading.button.centerXAnchor],
    [content.centerYAnchor constraintEqualToAnchor:loading.button.centerYAnchor]
  ]];
  [loading.shield addSubview:loading.button];
  void (^create)(UIView *) = model.customViewBlock;
  typeof(model.customViewLayoutBlock) layout = model.customViewLayoutBlock;
  model.customViewBlock = ^(UIView *parent) {
    if (create)
      create(parent);
    loading.contentView = parent;
    [parent addSubview:loading.shield];
  };
  model.customViewLayoutBlock = ^(CGSize screen, CGRect parent, CGRect name, CGRect other,
                                  CGRect nav, CGRect title, CGRect logo, CGRect slogan,
                                  CGRect number, CGRect login, CGRect change, CGRect privacy) {
    if (layout)
      layout(screen, parent, name, other, nav, title, logo, slogan, number, login, change, privacy);
    loading.shield.frame = loading.shield.superview.bounds;
    loading.button.frame = login;
    [loading.shield.superview bringSubviewToFront:loading.shield];
  };
  return loading;
}

@implementation AFLoginCardControls
- (instancetype)init {
  self = [super init];
  if (self) {
    _consentPromptButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _consentPromptButton.accessibilityHint = @"请先阅读并勾选同意下方协议";
    _emailButton = [UIButton buttonWithType:UIButtonTypeSystem];
  }
  return self;
}
- (void)setCarrierConsent:(BOOL)accepted {
  self.consentPromptButton.hidden = accepted;
}
@end

BOOL AFValidLoginCard(id value) {
  if (![value isKindOfClass:NSDictionary.class])
    return NO;
  for (NSString *key in @[
         @"x", @"y", @"width", @"height", @"textScale", @"backgroundColor", @"primaryColor",
         @"textColor", @"secondaryTextColor"
       ]) {
    id number = value[key];
    if (![number isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)number) == CFBooleanGetTypeID() ||
        !isfinite([number doubleValue]))
      return NO;
  }
  id title = value[@"title"];
  return [value[@"x"] doubleValue] >= 0 && [value[@"y"] doubleValue] >= 0 &&
         [value[@"width"] doubleValue] >= 240 && [value[@"height"] doubleValue] >= 400 &&
         [value[@"textScale"] doubleValue] >= 1 && [value[@"textScale"] doubleValue] <= 1.5 &&
         [title isKindOfClass:NSString.class] &&
         [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                 .length > 0;
}

static UIColor *AFCardColor(NSNumber *value) {
  uint32_t argb = value.unsignedIntValue;
  return [UIColor colorWithRed:((argb >> 16) & 255) / 255.0
                         green:((argb >> 8) & 255) / 255.0
                          blue:(argb & 255) / 255.0
                         alpha:((argb >> 24) & 255) / 255.0];
}

static UIImage *AFButtonImage(UIColor *color) {
  UIGraphicsImageRenderer *renderer =
      [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(40, 50)];
  UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
    [color setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 40, 50) cornerRadius:8] fill];
  }];
  return [image resizableImageWithCapInsets:UIEdgeInsetsMake(20, 18, 20, 18)];
}

AFLoginCardControls *AFConfigureLoginCard(AlicomFusionNumberAuthModel *model, NSDictionary *card,
                                          NSString *emailLabel) {
  UIColor *primary = AFCardColor(card[@"primaryColor"]);
  UIColor *text = AFCardColor(card[@"textColor"]);
  UIColor *secondary = AFCardColor(card[@"secondaryTextColor"]);
  CGFloat scale = [card[@"textScale"] doubleValue];
  CGFloat width = [card[@"width"] doubleValue];
  AFLoginCardControls *controls = [AFLoginCardControls new];
  CGRect desired = CGRectMake([card[@"x"] doubleValue], [card[@"y"] doubleValue], width,
                              [card[@"height"] doubleValue]);
  model.contentViewFrameBlock = ^CGRect(CGSize screen, CGSize parent, CGRect frame) {
    CGFloat w = MIN(desired.size.width, screen.width - 24);
    CGFloat h = MIN(desired.size.height, screen.height - 24);
    return CGRectMake(MIN(desired.origin.x, screen.width - w - 12),
                      MIN(desired.origin.y, screen.height - h - 12), w, h);
  };
  model.backgroundColor = AFCardColor(card[@"backgroundColor"]);
  model.alertBlurViewAlpha = 0;
  model.alertCornerRadiusArray = @[ @0, @0, @0, @0 ];
  model.alertBarIsHidden = YES;
  model.alertCloseItemIsHidden = YES;
  model.navIsHidden = YES;
  model.logoIsHidden = YES;
  model.animationDuration = 0;
  model.numberColor = text;
  // Reserve equal space on both sides so the number stays centered while the
  // right-hand change-number action remains separate, including narrow cards.
  model.numberFont =
      [UIFont monospacedDigitSystemFontOfSize:MIN(28 * scale, MAX(16, (width - 128) / 7.3))
                                       weight:UIFontWeightSemibold];
  model.numberFrameBlock = ^CGRect(CGSize screen, CGSize parent, CGRect frame) {
    return CGRectMake((parent.width - frame.size.width) / 2, 18, frame.size.width,
                      frame.size.height);
  };
  model.otherLoginButtonFrameBlock = ^CGRect(CGSize screen, CGSize parent, CGRect frame) {
    return CGRectMake(parent.width - 56, 13, 56, 44);
  };
  [model.otherLoginButton setTitleColor:primary forState:UIControlStateNormal];
  model.otherLoginButton.titleLabel.font = [UIFont systemFontOfSize:14 * scale
                                                             weight:UIFontWeightMedium];
  model.nameLabel = [[UILabel alloc] init];
  model.nameLabel.hidden = YES;
  model.nameLabelFrameBlock = ^CGRect(CGSize screen, CGSize parent, CGRect frame) {
    return CGRectMake(0, 1, parent.width, 0);
  };
  model.sloganIsHidden = YES;
  model.loginBtnText = [[NSAttributedString alloc]
      initWithString:card[@"title"]
          attributes:@{
            NSFontAttributeName : [UIFont systemFontOfSize:16 * scale weight:UIFontWeightSemibold],
            NSForegroundColorAttributeName : UIColor.whiteColor
          }];
  UIImage *button = AFButtonImage(primary);
  model.loginBtnBgImgs = @[ button, button, button ];
  model.loginBtnFrameBlock = ^CGRect(CGSize screen, CGSize parent, CGRect frame) {
    return CGRectMake(0, 80, parent.width, 50);
  };
  model.privacyFont = [UIFont systemFontOfSize:13 * scale weight:UIFontWeightSemibold];
  model.privacyAlignment = NSTextAlignmentLeft;
  model.checkBoxImageEdgeInsets = UIEdgeInsetsZero;
  model.privacyColors = @[ secondary, primary ];
  model.checkBoxWH = 20;
  model.privacyFrameBlock = ^CGRect(CGSize screen, CGSize parent, CGRect frame) {
    CGFloat height = MAX(84 * scale, frame.size.height);
    return CGRectMake(0, MAX(284, parent.height - height), parent.width, height);
  };
  UIFont *entryFont = [UIFont systemFontOfSize:13 * scale];
  model.changeBtnTitle = [[NSAttributedString alloc]
      initWithString:model.changeBtnTitle.string ?: @"密码登录"
          attributes:@{NSFontAttributeName : entryFont, NSForegroundColorAttributeName : primary}];
  CGFloat passwordWidth = ceil(
      [model.changeBtnTitle.string sizeWithAttributes:@{NSFontAttributeName : entryFont}].width);
  CGFloat emailWidth =
      ceil([emailLabel sizeWithAttributes:@{NSFontAttributeName : entryFont}].width);
  model.changeBtnFrameBlock = ^CGRect(CGSize screen, CGSize parent, CGRect frame) {
    CGFloat groupWidth = passwordWidth + 24 + emailWidth;
    return CGRectMake(emailLabel.length ? (parent.width - groupWidth) / 2 : 0, 142,
                      emailLabel.length ? passwordWidth : parent.width, 40);
  };
  UIButton *prompt = controls.consentPromptButton;
  prompt.accessibilityLabel = model.loginBtnText.string;
  [prompt setAttributedTitle:model.loginBtnText forState:UIControlStateNormal];
  [prompt setBackgroundImage:button forState:UIControlStateNormal];
  // Before consent, this normal-looking button only presents a reminder.
  // After consent, the original SDK button handles authorization.
  prompt.backgroundColor = AFCardColor(card[@"backgroundColor"]);
  prompt.layer.cornerRadius = 8;
  prompt.clipsToBounds = YES;
  UIButton *email = controls.emailButton;
  [email setTitle:emailLabel forState:UIControlStateNormal];
  [email setTitleColor:primary forState:UIControlStateNormal];
  email.titleLabel.font = entryFont;
  email.titleLabel.adjustsFontSizeToFitWidth = YES;
  email.titleLabel.minimumScaleFactor = 0.8;
  email.hidden = !emailLabel.length;
  UIView *entryDivider = [UIView new];
  entryDivider.backgroundColor = [secondary colorWithAlphaComponent:0.45];
  entryDivider.userInteractionEnabled = NO;
  entryDivider.isAccessibilityElement = NO;
  entryDivider.hidden = email.hidden || model.changeBtnIsHidden;
  model.customViewBlock = ^(UIView *parent) {
    [parent addSubview:controls.consentPromptButton];
    [parent addSubview:entryDivider];
    [parent addSubview:email];
  };
  model.customViewLayoutBlock = ^(CGSize screen, CGRect content, CGRect name, CGRect other,
                                  CGRect nav, CGRect title, CGRect logo, CGRect slogan,
                                  CGRect number, CGRect login, CGRect change, CGRect privacy) {
    controls.consentPromptButton.frame = login;
    email.frame = CGRectMake(CGRectGetMaxX(change) + 24, change.origin.y,
                             MIN(emailWidth, content.size.width - CGRectGetMaxX(change) - 24),
                             change.size.height);
    entryDivider.frame =
        CGRectMake(CGRectGetMaxX(change) + 11.5, CGRectGetMidY(change) - 7 * scale, 1, 14 * scale);
    [controls.consentPromptButton.superview bringSubviewToFront:controls.consentPromptButton];
    [email.superview bringSubviewToFront:email];
  };
  return controls;
}
