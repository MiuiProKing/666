#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static UIColor *NBPurple(void) { return [UIColor colorWithRed:0.49 green:0.20 blue:1.00 alpha:1.0]; }
static UIColor *NBCyan(void) { return [UIColor colorWithRed:0.00 green:0.88 blue:1.00 alpha:1.0]; }
static UIColor *NBBlack(void) { return [UIColor blackColor]; }
static UIColor *NBPanel(void) { return [UIColor colorWithRed:0.035 green:0.025 blue:0.075 alpha:1.0]; }
static UIColor *NBSecondary(void) { return [UIColor colorWithRed:0.68 green:0.62 blue:0.98 alpha:1.0]; }

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
    if (saturation < 0.16 && luminance < 0.28) return [UIColor colorWithWhite:0.97 alpha:a];
    if (saturation < 0.16 && luminance >= 0.28 && luminance < 0.72) return [NBSecondary() colorWithAlphaComponent:a];
    return color;
}

static void NBSetTextColor(id self, SEL _cmd, UIColor *color) {
    ((void (*)(id, SEL, UIColor *))NBOriginalSetTextColor)(self, _cmd, NBMappedText(color));
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

__attribute__((constructor)) static void NBInitialize(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NBHookGlobalAMOLED();
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
    });
}
