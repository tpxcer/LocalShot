#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

static CFMutableSetRef visited;
static NSInteger visitedCount;

static NSString *StringAttribute(AXUIElementRef element, CFStringRef attribute) {
    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(element, attribute, &value) != kAXErrorSuccess || !value) {
        return @"";
    }
    NSString *result = @"";
    if (CFGetTypeID(value) == CFStringGetTypeID()) {
        result = [(__bridge NSString *)value copy];
    }
    CFRelease(value);
    return result;
}

static NSArray<NSString *> *ActionNames(AXUIElementRef element) {
    CFArrayRef names = NULL;
    if (AXUIElementCopyActionNames(element, &names) != kAXErrorSuccess || !names) {
        return @[];
    }
    NSArray<NSString *> *result = [(__bridge NSArray *)names copy];
    CFRelease(names);
    return result;
}

static void Walk(AXUIElementRef element, NSInteger depth) {
    if (!element || depth > 16 || visitedCount >= 4000 || CFSetContainsValue(visited, element)) {
        return;
    }
    CFSetAddValue(visited, element);
    visitedCount += 1;

    NSString *role = StringAttribute(element, kAXRoleAttribute);
    NSString *subrole = StringAttribute(element, kAXSubroleAttribute);
    NSString *title = StringAttribute(element, kAXTitleAttribute);
    NSString *description = StringAttribute(element, kAXDescriptionAttribute);
    NSArray<NSString *> *actions = ActionNames(element);
    BOOL relevantRole = [@[
        @"AXApplication", @"AXWindow", @"AXScrollArea", @"AXWebArea", @"AXGroup"
    ] containsObject:role];
    BOOL hasScrollAction = NO;
    for (NSString *action in actions) {
        if ([action rangeOfString:@"scroll" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            hasScrollAction = YES;
            break;
        }
    }
    if (relevantRole || hasScrollAction) {
        printf(
            "%*srole=%s subrole=%s title=%s description=%s actions=%s\n",
            (int)(depth * 2), "",
            role.UTF8String, subrole.UTF8String, title.UTF8String, description.UTF8String,
            [actions componentsJoinedByString:@","].UTF8String
        );
    }

    if ([role isEqualToString:@"AXApplication"]) {
        return;
    }

    CFTypeRef childrenValue = NULL;
    if (AXUIElementCopyAttributeValue(element, kAXChildrenAttribute, &childrenValue) == kAXErrorSuccess
        && childrenValue && CFGetTypeID(childrenValue) == CFArrayGetTypeID()) {
        CFArrayRef children = (CFArrayRef)childrenValue;
        for (CFIndex index = 0; index < CFArrayGetCount(children); index++) {
            CFTypeRef child = CFArrayGetValueAtIndex(children, index);
            if (child && CFGetTypeID(child) == AXUIElementGetTypeID()) {
                Walk((AXUIElementRef)child, depth + 1);
            }
        }
    }
    if (childrenValue) {
        CFRelease(childrenValue);
    }
}

int main(void) {
    @autoreleasepool {
        if (!AXIsProcessTrusted()) {
            fprintf(stderr, "当前进程没有辅助功能权限\n");
            return 2;
        }
        NSArray<NSRunningApplication *> *applications = [NSRunningApplication
            runningApplicationsWithBundleIdentifier:@"com.google.Chrome"];
        NSRunningApplication *chrome = applications.firstObject;
        if (!chrome) {
            fprintf(stderr, "Chrome 未运行\n");
            return 3;
        }
        printf("chrome-apps=%ld selected-pid=%d name=%s executable=%s\n",
            (long)applications.count,
            chrome.processIdentifier,
            chrome.localizedName.UTF8String,
            chrome.executableURL.path.UTF8String);
        visited = CFSetCreateMutable(kCFAllocatorDefault, 0, NULL);
        AXUIElementRef application = AXUIElementCreateApplication(chrome.processIdentifier);
        AXUIElementSetAttributeValue(application, CFSTR("AXManualAccessibility"), kCFBooleanTrue);
        AXUIElementSetAttributeValue(application, CFSTR("AXEnhancedUserInterface"), kCFBooleanTrue);
        Walk(application, 0);

        CFTypeRef windowsValue = NULL;
        if (AXUIElementCopyAttributeValue(application, kAXWindowsAttribute, &windowsValue) == kAXErrorSuccess
            && windowsValue && CFGetTypeID(windowsValue) == CFArrayGetTypeID()) {
            CFArrayRef windows = (CFArrayRef)windowsValue;
            printf("windows=%ld\n", (long)CFArrayGetCount(windows));
            for (CFIndex index = 0; index < CFArrayGetCount(windows); index++) {
                CFTypeRef window = CFArrayGetValueAtIndex(windows, index);
                if (window && CFGetTypeID(window) == AXUIElementGetTypeID()) {
                    CFStringRef description = CFCopyDescription(window);
                    printf("window-index=%ld pointer=%p equal-app=%d cf=%s\n",
                        (long)index,
                        window,
                        CFEqual(window, application),
                        [(__bridge NSString *)description UTF8String]);
                    CFRelease(description);
                    Walk((AXUIElementRef)window, 1);
                }
            }
        }
        if (windowsValue) {
            CFRelease(windowsValue);
        }
        CGPoint points[] = {
            CGPointMake(1280, 720),
            CGPointMake(800, 400),
            CGPointMake(500, 500)
        };
        for (NSUInteger index = 0; index < sizeof(points) / sizeof(points[0]); index++) {
            AXUIElementRef hit = NULL;
            AXError error = AXUIElementCopyElementAtPosition(
                application,
                points[index].x,
                points[index].y,
                &hit
            );
            printf("hit point=(%.0f,%.0f) error=%d\n", points[index].x, points[index].y, error);
            if (hit) {
                CFStringRef description = CFCopyDescription(hit);
                printf("hit pointer=%p equal-app=%d cf=%s role=%s actions=%s\n",
                    hit,
                    CFEqual(hit, application),
                    [(__bridge NSString *)description UTF8String],
                    StringAttribute(hit, kAXRoleAttribute).UTF8String,
                    [ActionNames(hit) componentsJoinedByString:@","].UTF8String);
                CFRelease(description);
                Walk(hit, 1);
                CFRelease(hit);
            }
        }
        printf("visited=%ld\n", (long)visitedCount);
        CFRelease(application);
        CFRelease(visited);
    }
    return 0;
}
