#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static UIColor *NBPurple(void) { return [UIColor colorWithRed:0.49 green:0.20 blue:1.00 alpha:1.0]; }
static UIColor *NBCyan(void) { return [UIColor colorWithRed:0.00 green:0.88 blue:1.00 alpha:1.0]; }
static UIColor *NBBlack(void) { return [UIColor blackColor]; }
static UIColor *NBPanel(void) { return [UIColor colorWithRed:0.035 green:0.025 blue:0.075 alpha:1.0]; }
static UIColor *NBSecondary(void) { return [UIColor colorWithRed:0.82 green:0.86 blue:0.94 alpha:1.0]; }

typedef struct {
    Class cls;
    IMP viewDidAppear;
    IMP viewDidLayout;
} NBHookedClass;

static NBHookedClass NBHooks[32];
static NSUInteger NBHookCount = 0;
static IMP NBOriginalCellForRow = NULL;
static IMP NBOriginalDidSelect = NULL;
static IMP NBOriginalSetBackgroundColor = NULL;
static IMP NBOriginalSetTextColor = NULL;
static IMP NBOriginalTextViewSetTextColor = NULL;
static IMP NBOriginalTextFieldSetTextColor = NULL;
static IMP NBOriginalSetAttributedText = NULL;
static IMP NBOriginalSessionStartRunning = NULL;

static NSString * const NBProfileKey = @"NeonBee.Tigr.Profile";
static NSString * const NBFramesKey = @"NeonBee.Tigr.Frames";
static NSString * const NBHDRKey = @"NeonBee.Tigr.HDR";
static NSString * const NBNRKey = @"NeonBee.Tigr.NoiseReduction";
static NSString * const NBSharpnessKey = @"NeonBee.Tigr.Sharpness";
static NSString * const NBSaturationKey = @"NeonBee.Tigr.Saturation";
static NSString * const NBExposureKey = @"NeonBee.Tigr.Exposure";
static NSString * const NBEnabledKey = @"NeonBee.Tigr.Enabled";

static BOOL NBColorComponents(UIColor *color, CGFloat *red, CGFloat *green, CGFloat *blue, CGFloat *alpha) {
    if (!color) return NO;
    if ([color getRed:red green:green blue:blue alpha:alpha]) return YES;
    CGFloat white = 0.0;
    if ([color getWhite:&white alpha:alpha]) {
        *red = *green = *blue = white;
        return YES;
    }
    return NO;
}

static UIColor *NBMappedBackground(UIView *view, UIColor *color) {
    CGFloat r, g, b, a;
    if (!NBColorComponents(color, &r, &g, &b, &a) || a < 0.08) return color;
    CGFloat maximum = MAX(r, MAX(g, b));
    CGFloat minimum = MIN(r, MIN(g, b));
    CGFloat luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    CGFloat saturation = maximum > 0.001 ? (maximum - minimum) / maximum : 0.0;
    if (luminance > 0.78 && saturation < 0.16) {
        if ([view isKindOfClass:UIButton.class] || [view isKindOfClass:UITableViewCell.class]) return NBPanel();
        return NBBlack();
    }
    return color;
}

static void NBSetBackgroundColor(id self, SEL _cmd, UIColor *color) {
    UIColor *mapped = NBMappedBackground((UIView *)self, color);
    ((void (*)(id, SEL, UIColor *))NBOriginalSetBackgroundColor)(self, _cmd, mapped);
}

static UIColor *NBMappedText(UIColor *color) {
    CGFloat r, g, b, a;
    if (!NBColorComponents(color, &r, &g, &b, &a) || a < 0.08) return color;
    CGFloat maximum = MAX(r, MAX(g, b));
    CGFloat minimum = MIN(r, MIN(g, b));
    CGFloat luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    CGFloat saturation = maximum > 0.001 ? (maximum - minimum) / maximum : 0.0;
    if (saturation < 0.20 && luminance < 0.58) return [UIColor colorWithWhite:1.0 alpha:a];
    if (saturation < 0.20 && luminance >= 0.58 && luminance < 0.90) return [NBSecondary() colorWithAlphaComponent:a];
    return color;
}

static void NBSetTextColor(id self, SEL _cmd, UIColor *color) {
    ((void (*)(id, SEL, UIColor *))NBOriginalSetTextColor)(self, _cmd, NBMappedText(color));
}

static void NBTextViewSetTextColor(id self, SEL _cmd, UIColor *color) {
    ((void (*)(id, SEL, UIColor *))NBOriginalTextViewSetTextColor)(self, _cmd, NBMappedText(color));
}

static void NBTextFieldSetTextColor(id self, SEL _cmd, UIColor *color) {
    ((void (*)(id, SEL, UIColor *))NBOriginalTextFieldSetTextColor)(self, _cmd, NBMappedText(color));
}

static NSAttributedString *NBReadableAttributedString(NSAttributedString *source) {
    if (!source || source.length == 0) return source;
    NSMutableAttributedString *result = [source mutableCopy];
    [source enumerateAttribute:NSForegroundColorAttributeName
                       inRange:NSMakeRange(0, source.length)
                       options:0
                    usingBlock:^(UIColor *color, NSRange range, __unused BOOL *stop) {
        if (![color isKindOfClass:UIColor.class]) return;
        UIColor *mapped = NBMappedText(color);
        if (mapped != color) [result addAttribute:NSForegroundColorAttributeName value:mapped range:range];
    }];
    return result;
}

static void NBSetAttributedText(id self, SEL _cmd, NSAttributedString *text) {
    ((void (*)(id, SEL, NSAttributedString *))NBOriginalSetAttributedText)(self, _cmd, NBReadableAttributedString(text));
}

static void NBHookGlobalAMOLED(void) {
    Method backgroundMethod = class_getInstanceMethod(UIView.class, @selector(setBackgroundColor:));
    if (backgroundMethod) {
        NBOriginalSetBackgroundColor = method_getImplementation(backgroundMethod);
        method_setImplementation(backgroundMethod, (IMP)NBSetBackgroundColor);
    }
    Method textMethod = class_getInstanceMethod(UILabel.class, @selector(setTextColor:));
    if (textMethod) {
        NBOriginalSetTextColor = method_getImplementation(textMethod);
        method_setImplementation(textMethod, (IMP)NBSetTextColor);
    }
    Method attributedMethod = class_getInstanceMethod(UILabel.class, @selector(setAttributedText:));
    if (attributedMethod) {
        NBOriginalSetAttributedText = method_getImplementation(attributedMethod);
        method_setImplementation(attributedMethod, (IMP)NBSetAttributedText);
    }
    Method textViewMethod = class_getInstanceMethod(UITextView.class, @selector(setTextColor:));
    if (textViewMethod) {
        NBOriginalTextViewSetTextColor = method_getImplementation(textViewMethod);
        method_setImplementation(textViewMethod, (IMP)NBTextViewSetTextColor);
    }
    Method textFieldMethod = class_getInstanceMethod(UITextField.class, @selector(setTextColor:));
    if (textFieldMethod) {
        NBOriginalTextFieldSetTextColor = method_getImplementation(textFieldMethod);
        method_setImplementation(textFieldMethod, (IMP)NBTextFieldSetTextColor);
    }

    UINavigationBarAppearance *navigation = [UINavigationBarAppearance new];
    [navigation configureWithOpaqueBackground];
    navigation.backgroundColor = NBBlack();
    navigation.shadowColor = [NBPurple() colorWithAlphaComponent:0.30];
    navigation.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.whiteColor};
    UINavigationBar *navigationBar = UINavigationBar.appearance;
    navigationBar.standardAppearance = navigation;
    navigationBar.scrollEdgeAppearance = navigation;
    navigationBar.compactAppearance = navigation;
    navigationBar.tintColor = NBCyan();

    UITabBarAppearance *tabs = [UITabBarAppearance new];
    [tabs configureWithOpaqueBackground];
    tabs.backgroundColor = NBBlack();
    tabs.shadowColor = [NBPurple() colorWithAlphaComponent:0.30];
    UITabBar *tabBar = UITabBar.appearance;
    tabBar.standardAppearance = tabs;
    if (@available(iOS 15.0, *)) tabBar.scrollEdgeAppearance = tabs;
    tabBar.tintColor = NBPurple();
    tabBar.unselectedItemTintColor = [UIColor colorWithWhite:0.55 alpha:1.0];

    UITableView.appearance.backgroundColor = NBBlack();
    UITableView.appearance.separatorColor = [NBPurple() colorWithAlphaComponent:0.20];
    UICollectionView.appearance.backgroundColor = NBBlack();
    UILabel.appearance.tintColor = NBCyan();
    UITextView.appearance.backgroundColor = NBBlack();
    UITextView.appearance.textColor = UIColor.whiteColor;
    UITextField.appearance.textColor = UIColor.whiteColor;
}

static BOOL NBIsSettingsController(UIViewController *controller) {
    NSString *name = NSStringFromClass(controller.class);
    return [name isEqualToString:@"SettingsViewController"] ||
           [name hasSuffix:@"SettingsViewController"] ||
           [name isEqualToString:@"CustomizationViewController"] ||
           [name isEqualToString:@"LanguageSettingsViewController"] ||
           [name isEqualToString:@"ProfileAnalyzerViewController"] ||
           [name isEqualToString:@"GhostModeViewController"];
}

static void NBCollectLabels(UIView *view, NSMutableArray<UILabel *> *labels) {
    if ([view isKindOfClass:UILabel.class]) [labels addObject:(UILabel *)view];
    for (UIView *child in view.subviews) NBCollectLabels(child, labels);
}

static void NBApplyOwnerCard(UITableViewCell *cell) {
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    NBCollectLabels(cell.contentView, labels);
    [labels sortUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) {
        CGFloat ay = [a convertPoint:CGPointZero toView:cell].y;
        CGFloat by = [b convertPoint:CGPointZero toView:cell].y;
        return ay < by ? NSOrderedAscending : (ay > by ? NSOrderedDescending : NSOrderedSame);
    }];
    if (labels.count > 0) {
        labels[0].text = @"\u0412\u044f\u0447\u0435\u0441\u043b\u0430\u0432";
        labels[0].textColor = UIColor.whiteColor;
    }
    if (labels.count > 1) {
        labels[1].text = @"Instagram @vyacheslavvya  |  Telegram @VOXFF3";
        labels[1].textColor = NBCyan();
        labels[1].adjustsFontSizeToFitWidth = YES;
        labels[1].minimumScaleFactor = 0.72;
    }
    UIImage *avatar = [UIImage systemImageNamed:@"person.crop.circle.badge.checkmark"];
    for (UIView *child in cell.contentView.subviews) {
        if ([child isKindOfClass:UIImageView.class] && child.bounds.size.width >= 28.0 && child.bounds.size.width <= 60.0) {
            UIImageView *imageView = (UIImageView *)child;
            imageView.image = [avatar imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            imageView.tintColor = NBPurple();
            break;
        }
    }
    cell.accessibilityLabel = @"\u041a\u043e\u043d\u0442\u0430\u043a\u0442\u044b \u0412\u044f\u0447\u0435\u0441\u043b\u0430\u0432\u0430";
    cell.accessibilityHint = @"Instagram / Telegram";
}

static void NBThemeView(UIView *view) {
    if ([view isKindOfClass:UITableView.class]) {
        UITableView *table = (UITableView *)view;
        table.backgroundColor = NBBlack();
        table.separatorColor = [NBPurple() colorWithAlphaComponent:0.22];
        table.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    } else if ([view isKindOfClass:UITableViewCell.class]) {
        UITableViewCell *cell = (UITableViewCell *)view;
        cell.backgroundColor = NBPanel();
        cell.contentView.backgroundColor = NBPanel();
        cell.tintColor = NBPurple();
        cell.layer.borderColor = [NBPurple() colorWithAlphaComponent:0.28].CGColor;
        cell.layer.borderWidth = 0.45;
        cell.layer.shadowColor = NBPurple().CGColor;
        cell.layer.shadowOpacity = 0.12;
        cell.layer.shadowRadius = 8.0;
        cell.layer.shadowOffset = CGSizeZero;
    } else if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        label.textColor = label.font.pointSize < 16.5 ? NBSecondary() : UIColor.whiteColor;
    } else if ([view isKindOfClass:UIImageView.class]) {
        UIImageView *imageView = (UIImageView *)view;
        if (imageView.image) {
            imageView.image = [imageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            imageView.tintColor = NBPurple();
        }
    } else if ([view isKindOfClass:UISwitch.class]) {
        UISwitch *toggle = (UISwitch *)view;
        toggle.onTintColor = NBPurple();
        toggle.thumbTintColor = UIColor.whiteColor;
    } else if ([view isKindOfClass:UITextField.class]) {
        UITextField *field = (UITextField *)view;
        field.textColor = UIColor.whiteColor;
        field.tintColor = NBCyan();
        field.backgroundColor = NBPanel();
    } else if (![view isKindOfClass:UIVisualEffectView.class]) {
        UIColor *background = view.backgroundColor;
        if (background && CGColorGetAlpha(background.CGColor) > 0.05) view.backgroundColor = NBBlack();
    }

    for (UIView *child in view.subviews) NBThemeView(child);
}

static void NBRefreshOwnerRow(UIViewController *controller) {
    if (![NSStringFromClass(controller.class) isEqualToString:@"SettingsViewController"]) return;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:controller.view];
    while (stack.count) {
        UIView *view = stack.lastObject;
        [stack removeLastObject];
        if ([view isKindOfClass:UITableView.class]) {
            UITableView *table = (UITableView *)view;
            NSIndexPath *ownerPath = [NSIndexPath indexPathForRow:0 inSection:2];
            UITableViewCell *cell = [table cellForRowAtIndexPath:ownerPath];
            if (cell) NBApplyOwnerCard(cell);
        }
        [stack addObjectsFromArray:view.subviews];
    }
}

static void NBApplyTheme(UIViewController *controller) {
    if (!NBIsSettingsController(controller) || !controller.isViewLoaded) return;
    controller.view.backgroundColor = NBBlack();
    controller.navigationController.view.backgroundColor = NBBlack();
    UINavigationBar *bar = controller.navigationController.navigationBar;
    if (bar) {
        UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = NBBlack();
        appearance.shadowColor = [NBPurple() colorWithAlphaComponent:0.35];
        appearance.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.whiteColor};
        bar.standardAppearance = appearance;
        bar.scrollEdgeAppearance = appearance;
        bar.compactAppearance = appearance;
        bar.tintColor = NBCyan();
    }
    NBThemeView(controller.view);
    NBRefreshOwnerRow(controller);
}

static IMP NBOriginalForObject(id object, BOOL layout) {
    Class cls = object_getClass(object);
    for (NSUInteger i = 0; i < NBHookCount; i++) {
        if (NBHooks[i].cls == cls) return layout ? NBHooks[i].viewDidLayout : NBHooks[i].viewDidAppear;
    }
    return NULL;
}

static void NBViewDidAppear(id self, SEL _cmd, BOOL animated) {
    IMP original = NBOriginalForObject(self, NO);
    if (original && original != (IMP)NBViewDidAppear) ((void (*)(id, SEL, BOOL))original)(self, _cmd, animated);
    NBApplyTheme((UIViewController *)self);
}

static void NBViewDidLayoutSubviews(id self, SEL _cmd) {
    IMP original = NBOriginalForObject(self, YES);
    if (original && original != (IMP)NBViewDidLayoutSubviews) ((void (*)(id, SEL))original)(self, _cmd);
    NBApplyTheme((UIViewController *)self);
}

static void NBInstallViewHook(Class cls, SEL selector, IMP replacement, IMP *storage) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return;
    IMP original = method_getImplementation(method);
    const char *types = method_getTypeEncoding(method);
    if (!class_addMethod(cls, selector, replacement, types)) method_setImplementation(method, replacement);
    *storage = original;
}

static UITableViewCell *NBCellForRow(id self, SEL _cmd, UITableView *table, NSIndexPath *path) {
    UITableViewCell *cell = ((UITableViewCell *(*)(id, SEL, UITableView *, NSIndexPath *))NBOriginalCellForRow)(self, _cmd, table, path);
    if (path.section == 2 && path.row == 0) NBApplyOwnerCard(cell);
    return cell;
}

static void NBOpenWebURL(NSString *urlString) {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

static void NBShowContacts(UIViewController *controller, UITableView *table, NSIndexPath *path) {
    [table deselectRowAtIndexPath:path animated:YES];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"\u041a\u043e\u043d\u0442\u0430\u043a\u0442\u044b \u0412\u044f\u0447\u0435\u0441\u043b\u0430\u0432\u0430"
                                                                    message:@"Instagram / Telegram"
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Instagram  @vyacheslavvya" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NBOpenWebURL(@"https://www.instagram.com/vyacheslavvya/");
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Telegram  @VOXFF3" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NBOpenWebURL(@"https://t.me/VOXFF3");
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover) {
        UITableViewCell *cell = [table cellForRowAtIndexPath:path];
        popover.sourceView = cell ?: table;
        popover.sourceRect = cell ? cell.bounds : table.bounds;
    }
    [controller presentViewController:sheet animated:YES completion:nil];
}

static void NBDidSelectRow(id self, SEL _cmd, UITableView *table, NSIndexPath *path) {
    if (path.section == 2 && path.row == 0) {
        NBShowContacts((UIViewController *)self, table, path);
        return;
    }
    ((void (*)(id, SEL, UITableView *, NSIndexPath *))NBOriginalDidSelect)(self, _cmd, table, path);
}

static void NBHookSettingsTable(void) {
    Class cls = NSClassFromString(@"SettingsViewController");
    if (!cls) return;
    SEL cellSelector = @selector(tableView:cellForRowAtIndexPath:);
    Method cellMethod = class_getInstanceMethod(cls, cellSelector);
    if (cellMethod) {
        NBOriginalCellForRow = method_getImplementation(cellMethod);
        if (!class_addMethod(cls, cellSelector, (IMP)NBCellForRow, method_getTypeEncoding(cellMethod))) {
            method_setImplementation(cellMethod, (IMP)NBCellForRow);
        }
    }
    SEL selectSelector = @selector(tableView:didSelectRowAtIndexPath:);
    Method selectMethod = class_getInstanceMethod(cls, selectSelector);
    if (selectMethod) {
        NBOriginalDidSelect = method_getImplementation(selectMethod);
        if (!class_addMethod(cls, selectSelector, (IMP)NBDidSelectRow, method_getTypeEncoding(selectMethod))) {
            method_setImplementation(selectMethod, (IMP)NBDidSelectRow);
        }
    }
}

static void NBRegisterTigrDefaults(void) {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        NBProfileKey: @1,
        NBFramesKey: @8,
        NBHDRKey: @0.78,
        NBNRKey: @0.48,
        NBSharpnessKey: @0.56,
        NBSaturationKey: @1.08,
        NBExposureKey: @-0.15,
        NBEnabledKey: @YES
    }];
}

static float NBClampFloat(float value, float minimum, float maximum) {
    return MIN(maximum, MAX(minimum, value));
}

static void NBApplyTigrToDevice(AVCaptureDevice *device) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (![defaults boolForKey:NBEnabledKey] || !device) return;
    NSError *error = nil;
    if (![device lockForConfiguration:&error]) return;
    float bias = (float)[defaults doubleForKey:NBExposureKey];
    bias = NBClampFloat(bias, device.minExposureTargetBias, device.maxExposureTargetBias);
    [device setExposureTargetBias:bias completionHandler:nil];
    if ([device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
        device.focusMode = AVCaptureFocusModeContinuousAutoFocus;
    }
    if ([device isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance]) {
        device.whiteBalanceMode = AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance;
    }
    if (device.isLowLightBoostSupported) {
        device.automaticallyEnablesLowLightBoostWhenAvailable = ([defaults integerForKey:NBProfileKey] == 2);
    }
    device.subjectAreaChangeMonitoringEnabled = YES;
    [device unlockForConfiguration];
}

static void NBSessionStartRunning(id self, SEL _cmd) {
    ((void (*)(id, SEL))NBOriginalSessionStartRunning)(self, _cmd);
    AVCaptureSession *session = (AVCaptureSession *)self;
    for (AVCaptureInput *input in session.inputs) {
        if ([input isKindOfClass:AVCaptureDeviceInput.class]) {
            NBApplyTigrToDevice(((AVCaptureDeviceInput *)input).device);
        }
    }
    NSInteger profile = [NSUserDefaults.standardUserDefaults integerForKey:NBProfileKey];
    for (AVCaptureOutput *output in session.outputs) {
        for (AVCaptureConnection *connection in output.connections) {
            if (connection.isVideoStabilizationSupported) {
                connection.preferredVideoStabilizationMode = profile == 2 ? AVCaptureVideoStabilizationModeCinematic : AVCaptureVideoStabilizationModeAuto;
            }
        }
    }
}

static void NBHookCameraSession(void) {
    Method method = class_getInstanceMethod(AVCaptureSession.class, @selector(startRunning));
    if (!method) return;
    NBOriginalSessionStartRunning = method_getImplementation(method);
    method_setImplementation(method, (IMP)NBSessionStartRunning);
}

static UIViewController *NBTopController(void) {
    UIWindow *keyWindow = nil;
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if (window.isKeyWindow) { keyWindow = window; break; }
    }
    UIViewController *controller = keyWindow.rootViewController;
    while (controller.presentedViewController) controller = controller.presentedViewController;
    if ([controller isKindOfClass:UINavigationController.class]) controller = ((UINavigationController *)controller).topViewController;
    if ([controller isKindOfClass:UITabBarController.class]) controller = ((UITabBarController *)controller).selectedViewController;
    return controller;
}

@interface NBTigrPanelController : UIViewController
@property(nonatomic, strong) UISegmentedControl *profileControl;
@property(nonatomic, strong) UISegmentedControl *framesControl;
@property(nonatomic, strong) UISwitch *enabledSwitch;
@property(nonatomic, strong) NSMutableDictionary<NSString *, UILabel *> *valueLabels;
@end

@implementation NBTigrPanelController

- (UILabel *)titleLabel:(NSString *)text size:(CGFloat)size color:(UIColor *)color {
    UILabel *label = [UILabel new];
    label.text = text;
    label.textColor = color;
    label.font = [UIFont systemFontOfSize:size weight:UIFontWeightSemibold];
    label.numberOfLines = 0;
    return label;
}

- (UIView *)sliderRow:(NSString *)title key:(NSString *)key minimum:(float)minimum maximum:(float)maximum {
    UIView *row = [UIView new];
    row.backgroundColor = NBPanel();
    row.layer.cornerRadius = 14.0;
    row.layer.borderWidth = 0.7;
    row.layer.borderColor = [NBPurple() colorWithAlphaComponent:0.45].CGColor;
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *name = [self titleLabel:title size:14.0 color:UIColor.whiteColor];
    UILabel *value = [self titleLabel:@"" size:13.0 color:NBCyan()];
    value.textAlignment = NSTextAlignmentRight;
    self.valueLabels[key] = value;
    UISlider *slider = [UISlider new];
    slider.minimumValue = minimum;
    slider.maximumValue = maximum;
    slider.value = (float)[NSUserDefaults.standardUserDefaults doubleForKey:key];
    slider.minimumTrackTintColor = NBPurple();
    slider.maximumTrackTintColor = [UIColor colorWithWhite:0.22 alpha:1.0];
    slider.tintColor = NBCyan();
    slider.accessibilityIdentifier = key;
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    value.text = [self displayValue:slider.value forKey:key];
    for (UIView *view in @[name, value, slider]) view.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:name]; [row addSubview:value]; [row addSubview:slider];
    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:72.0],
        [name.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:14.0],
        [name.topAnchor constraintEqualToAnchor:row.topAnchor constant:10.0],
        [value.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-14.0],
        [value.centerYAnchor constraintEqualToAnchor:name.centerYAnchor],
        [slider.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:14.0],
        [slider.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-14.0],
        [slider.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-8.0]
    ]];
    return row;
}

- (NSString *)displayValue:(float)value forKey:(NSString *)key {
    if ([key isEqualToString:NBSaturationKey]) return [NSString stringWithFormat:@"%.2fx", value];
    if ([key isEqualToString:NBExposureKey]) return [NSString stringWithFormat:@"%+.2f EV", value];
    return [NSString stringWithFormat:@"%.0f%%", value * 100.0f];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = NBBlack();
    self.valueLabels = [NSMutableDictionary dictionary];

    UIScrollView *scroll = [UIScrollView new];
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12.0;
    stack.layoutMargins = UIEdgeInsetsMake(22, 18, 28, 18);
    stack.layoutMarginsRelativeArrangement = YES;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll]; [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]
    ]];

    UILabel *title = [self titleLabel:@"TIGR CAMERA  вЂў  PRO" size:24.0 color:UIColor.whiteColor];
    title.layer.shadowColor = NBCyan().CGColor; title.layer.shadowOpacity = 0.8; title.layer.shadowRadius = 8.0;
    [stack addArrangedSubview:title];
    [stack addArrangedSubview:[self titleLabel:@"РџСЂРѕС„РёР»Рё РєР°РјРµСЂС‹ Beegram В· AMOLED Neon" size:13.0 color:NBSecondary()]];

    UIView *enabledRow = [UIView new]; enabledRow.backgroundColor = NBPanel(); enabledRow.layer.cornerRadius = 14.0;
    UILabel *enabledLabel = [self titleLabel:@"РџСЂРёРјРµРЅСЏС‚СЊ РЅР°СЃС‚СЂРѕР№РєРё Рє РєР°РјРµСЂРµ" size:15.0 color:UIColor.whiteColor];
    self.enabledSwitch = [UISwitch new]; self.enabledSwitch.onTintColor = NBPurple();
    self.enabledSwitch.on = [NSUserDefaults.standardUserDefaults boolForKey:NBEnabledKey];
    [self.enabledSwitch addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];
    for (UIView *view in @[enabledLabel, self.enabledSwitch]) view.translatesAutoresizingMaskIntoConstraints = NO;
    [enabledRow addSubview:enabledLabel]; [enabledRow addSubview:self.enabledSwitch];
    [NSLayoutConstraint activateConstraints:@[
        [enabledRow.heightAnchor constraintEqualToConstant:58.0],
        [enabledLabel.leadingAnchor constraintEqualToAnchor:enabledRow.leadingAnchor constant:14.0],
        [enabledLabel.centerYAnchor constraintEqualToAnchor:enabledRow.centerYAnchor],
        [self.enabledSwitch.trailingAnchor constraintEqualToAnchor:enabledRow.trailingAnchor constant:-14.0],
        [self.enabledSwitch.centerYAnchor constraintEqualToAnchor:enabledRow.centerYAnchor]
    ]];
    [stack addArrangedSubview:enabledRow];

    [stack addArrangedSubview:[self titleLabel:@"РџР РћР¤РР›Р¬" size:12.0 color:NBCyan()]];
    self.profileControl = [[UISegmentedControl alloc] initWithItems:@[@"РќР°С‚СѓСЂР°Р»СЊРЅС‹Р№", @"HDR", @"РќРѕС‡СЊ", @"Р›СЋРґРё"]];
    self.profileControl.selectedSegmentIndex = [NSUserDefaults.standardUserDefaults integerForKey:NBProfileKey];
    self.profileControl.selectedSegmentTintColor = NBPurple();
    [self.profileControl setTitleTextAttributes:@{NSForegroundColorAttributeName:UIColor.whiteColor} forState:UIControlStateNormal];
    [self.profileControl addTarget:self action:@selector(profileChanged:) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:self.profileControl];

    [stack addArrangedSubview:[self titleLabel:@"РљРђР”Р Р«" size:12.0 color:NBCyan()]];
    self.framesControl = [[UISegmentedControl alloc] initWithItems:@[@"3", @"5", @"8", @"12"]];
    NSInteger frames = [NSUserDefaults.standardUserDefaults integerForKey:NBFramesKey];
    self.framesControl.selectedSegmentIndex = frames == 3 ? 0 : frames == 5 ? 1 : frames == 12 ? 3 : 2;
    self.framesControl.selectedSegmentTintColor = NBCyan();
    [self.framesControl addTarget:self action:@selector(framesChanged:) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:self.framesControl];

    [stack addArrangedSubview:[self sliderRow:@"РЎРёР»Р° HDR" key:NBHDRKey minimum:0 maximum:1]];
    [stack addArrangedSubview:[self sliderRow:@"РЁСѓРјРѕРїРѕРґР°РІР»РµРЅРёРµ" key:NBNRKey minimum:0 maximum:1]];
    [stack addArrangedSubview:[self sliderRow:@"Р РµР·РєРѕСЃС‚СЊ Рё РґРµС‚Р°Р»Рё" key:NBSharpnessKey minimum:0 maximum:1]];
    [stack addArrangedSubview:[self sliderRow:@"РќР°СЃС‹С‰РµРЅРЅРѕСЃС‚СЊ" key:NBSaturationKey minimum:0.80 maximum:1.30]];
    [stack addArrangedSubview:[self sliderRow:@"Р­РєСЃРїРѕР·РёС†РёСЏ" key:NBExposureKey minimum:-1.0 maximum:1.0]];

    UILabel *note = [self titleLabel:@"Р¤РѕРєСѓСЃ, Р±Р°Р»Р°РЅСЃ Р±РµР»РѕРіРѕ, СЌРєСЃРїРѕР·РёС†РёСЏ, СЃС‚Р°Р±РёР»РёР·Р°С†РёСЏ Рё РЅРѕС‡РЅРѕР№ low-light РїСЂРёРјРµРЅСЏСЋС‚СЃСЏ С‡РµСЂРµР· AVFoundation. РџР°СЂР°РјРµС‚СЂС‹ HDR/РєР°РґСЂРѕРІ СЃРѕС…СЂР°РЅСЏСЋС‚СЃСЏ РєР°Рє РїСЂРѕС„РёР»СЊ Tigr РґР»СЏ СЃРѕРІРјРµСЃС‚РёРјРѕР№ РєР°РјРµСЂС‹ Beegram." size:12.0 color:NBSecondary()];
    [stack addArrangedSubview:note];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"Р“РћРўРћР’Рћ" forState:UIControlStateNormal]; close.tintColor = UIColor.whiteColor;
    close.backgroundColor = NBPurple(); close.layer.cornerRadius = 16.0; close.titleLabel.font = [UIFont boldSystemFontOfSize:17.0];
    [close.heightAnchor constraintEqualToConstant:52.0].active = YES;
    [close addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:close];
}

- (void)enabledChanged:(UISwitch *)sender { [NSUserDefaults.standardUserDefaults setBool:sender.isOn forKey:NBEnabledKey]; }
- (void)framesChanged:(UISegmentedControl *)sender {
    NSInteger values[] = {3, 5, 8, 12};
    [NSUserDefaults.standardUserDefaults setInteger:values[sender.selectedSegmentIndex] forKey:NBFramesKey];
}
- (void)sliderChanged:(UISlider *)sender {
    NSString *key = sender.accessibilityIdentifier;
    [NSUserDefaults.standardUserDefaults setDouble:sender.value forKey:key];
    self.valueLabels[key].text = [self displayValue:sender.value forKey:key];
}
- (void)profileChanged:(UISegmentedControl *)sender {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setInteger:sender.selectedSegmentIndex forKey:NBProfileKey];
    NSArray<NSDictionary *> *profiles = @[
        @{NBHDRKey:@0.52, NBNRKey:@0.32, NBSharpnessKey:@0.48, NBSaturationKey:@1.04, NBExposureKey:@-0.05},
        @{NBHDRKey:@0.78, NBNRKey:@0.48, NBSharpnessKey:@0.56, NBSaturationKey:@1.08, NBExposureKey:@-0.15},
        @{NBHDRKey:@0.68, NBNRKey:@0.78, NBSharpnessKey:@0.40, NBSaturationKey:@1.02, NBExposureKey:@0.30},
        @{NBHDRKey:@0.58, NBNRKey:@0.45, NBSharpnessKey:@0.42, NBSaturationKey:@1.03, NBExposureKey:@0.08}
    ];
    [profiles[sender.selectedSegmentIndex] enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSNumber *value, __unused BOOL *stop) {
        [defaults setObject:value forKey:key];
    }];
    [self dismissViewControllerAnimated:NO completion:^{
        UIViewController *top = NBTopController();
        NBTigrPanelController *panel = [NBTigrPanelController new];
        panel.modalPresentationStyle = UIModalPresentationPageSheet;
        [top presentViewController:panel animated:NO completion:nil];
    }];
}
- (void)closePanel { [self dismissViewControllerAnimated:YES completion:nil]; }
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
@end

@interface NBTigrOverlay : NSObject
@end

@implementation NBTigrOverlay
+ (instancetype)shared { static NBTigrOverlay *instance; static dispatch_once_t once; dispatch_once(&once, ^{ instance = [NBTigrOverlay new]; }); return instance; }
- (void)installButton {
    UIWindow *window = nil;
    for (UIWindow *candidate in UIApplication.sharedApplication.windows) if (candidate.isKeyWindow) { window = candidate; break; }
    if (!window || [window viewWithTag:0x54494752]) return;
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = 0x54494752; button.frame = CGRectMake(window.bounds.size.width - 54.0, window.bounds.size.height * 0.42, 44.0, 44.0);
    button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    UIImage *icon = [UIImage systemImageNamed:@"camera.filters"];
    [button setImage:icon forState:UIControlStateNormal];
    button.tintColor = UIColor.whiteColor; button.backgroundColor = [NBPanel() colorWithAlphaComponent:0.94];
    button.layer.cornerRadius = 22.0; button.layer.borderWidth = 1.2; button.layer.borderColor = NBCyan().CGColor;
    button.layer.shadowColor = NBPurple().CGColor; button.layer.shadowOpacity = 0.9; button.layer.shadowRadius = 10.0; button.layer.shadowOffset = CGSizeZero;
    button.accessibilityLabel = @"РќР°СЃС‚СЂРѕР№РєРё Tigr Camera";
    [button addTarget:self action:@selector(openPanel) forControlEvents:UIControlEventTouchUpInside];
    [button addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(moveButton:)]];
    [window addSubview:button]; [window bringSubviewToFront:button];
}
- (void)moveButton:(UIPanGestureRecognizer *)gesture {
    UIView *view = gesture.view; CGPoint delta = [gesture translationInView:view.superview];
    CGPoint center = view.center; center.x += delta.x; center.y += delta.y;
    center.x = MAX(28.0, MIN(view.superview.bounds.size.width - 28.0, center.x));
    center.y = MAX(70.0, MIN(view.superview.bounds.size.height - 90.0, center.y));
    view.center = center; [gesture setTranslation:CGPointZero inView:view.superview];
}
- (void)openPanel {
    UIViewController *top = NBTopController(); if (!top) return;
    NBTigrPanelController *panel = [NBTigrPanelController new];
    panel.modalPresentationStyle = UIModalPresentationPageSheet;
    [top presentViewController:panel animated:YES completion:nil];
}
@end

__attribute__((constructor)) static void NBInitialize(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NBRegisterTigrDefaults();
        NBHookGlobalAMOLED();
        NBHookCameraSession();
        NSArray<NSString *> *classNames = @[
            @"SettingsViewController", @"MessagesSettingsViewController", @"StoriesSettingsViewController",
            @"ReelsSettingsViewController", @"ProfileSettingsViewController", @"LanguageSettingsViewController",
            @"VoiceChangerSettingsViewController", @"CallRecorderSettingsViewController", @"CustomizationViewController",
            @"ProfileAnalyzerViewController", @"GhostModeViewController"
        ];
        for (NSString *name in classNames) {
            Class cls = NSClassFromString(name);
            if (!cls || NBHookCount >= 32) continue;
            NBHooks[NBHookCount].cls = cls;
            NBInstallViewHook(cls, @selector(viewDidAppear:), (IMP)NBViewDidAppear, &NBHooks[NBHookCount].viewDidAppear);
            NBInstallViewHook(cls, @selector(viewDidLayoutSubviews), (IMP)NBViewDidLayoutSubviews, &NBHooks[NBHookCount].viewDidLayout);
            NBHookCount++;
        }
        NBHookSettingsTable();
        [[NSNotificationCenter defaultCenter] addObserver:NBTigrOverlay.shared selector:@selector(installButton) name:UIApplicationDidBecomeActiveNotification object:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [NBTigrOverlay.shared installButton]; });
    });
}

