// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import <XCTest/XCTest.h>

#import "ATRDocumentBuilder.h"
#import "ATRTextDisplayView.h"

#include <cmath>

namespace {

ATRTextStyle fontStyle(int32_t font) {
    ATRTextStyle style = {};
    style.fields = ATRTextStyleFieldFont;
    style.font = font;
    return style;
}

void layoutNow(ATRPlatformView *view) {
#if TARGET_OS_OSX
    [view layoutSubtreeIfNeeded];
#else
    [view layoutIfNeeded];
#endif
}

NSUInteger tapCount(ATRPlatformGestureRecognizer *recognizer) {
#if TARGET_OS_OSX
    return [recognizer isKindOfClass:NSClickGestureRecognizer.class]
        ? ((NSClickGestureRecognizer *)recognizer).numberOfClicksRequired
        : 0;
#else
    return [recognizer isKindOfClass:UITapGestureRecognizer.class]
        ? ((UITapGestureRecognizer *)recognizer).numberOfTapsRequired
        : 0;
#endif
}

ATRPlatformImage *makeImage(CGSize size) {
#if TARGET_OS_OSX
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [NSColor.redColor setFill];
    NSRectFill(NSMakeRect(0, 0, size.width, size.height));
    [image unlockFocus];
    return image;
#else
    return [[[UIGraphicsImageRenderer alloc] initWithSize:size] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [UIColor.redColor setFill];
        [context fillRect:CGRectMake(0, 0, size.width, size.height)];
    }];
#endif
}

#if TARGET_OS_OSX
using TestWindow = NSWindow;
using TestScrollView = NSScrollView;
#else
using TestWindow = UIWindow;
using TestScrollView = UIScrollView;
#endif

TestWindow *makeWindow() {
#if TARGET_OS_OSX
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 320, 600)
                                                   styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    window.releasedWhenClosed = NO;
    return window;
#else
    return [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 320, 600)];
#endif
}

void addToWindow(ATRPlatformView *view, TestWindow *window) {
#if TARGET_OS_OSX
    [window.contentView addSubview:view];
#else
    [window addSubview:view];
#endif
}

// A scroll view with `content` as its scrolled content.
TestScrollView *makeScrollView(ATRPlatformView *content, CGSize contentSize) {
#if TARGET_OS_OSX
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 320, 300)];
    scrollView.documentView = content;
#else
    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, 320, 300)];
    scrollView.contentSize = contentSize;
    [scrollView addSubview:content];
#endif
    return scrollView;
}

} // namespace

@interface CountingTapFactory : NSObject <ATRGestureRecognizerFactory>
@property (nonatomic) NSUInteger count;
@end

@implementation CountingTapFactory {
    ATRTapGestureFactory *_base;
}

- (instancetype)init {
    self = [super init];
    _base = [[ATRTapGestureFactory alloc] init];
    return self;
}

- (ATRGestureBinding *)bindingForGesture:(ATRGesture)gesture
                             interaction:(uint32_t)interaction
                                 handler:(ATRGestureHandler)handler {
    self.count += 1;
    return [_base bindingForGesture:gesture interaction:interaction handler:handler];
}

@end

@interface DisplayViewTests : XCTestCase
@end

@implementation DisplayViewTests {
    uint32_t _doubleTap;
    uint32_t _singleTap;
    uint32_t _longPress;
}

// "Hello " plain, "dbl" with a double tap, "x" with a single tap nested in
// the double tap, and "hold" with a long press.
- (ATRDocument *)interactiveDocument {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    int32_t font = [builder registerFont:[ATRPlatformFont systemFontOfSize:30]];
    _doubleTap = [builder registerInteractionWithGesture:{ATRGestureKindTap, 2, 0}];
    _singleTap = [builder registerInteractionWithGesture:{ATRGestureKindTap, 1, 0}];
    _longPress = [builder registerInteractionWithGesture:{ATRGestureKindLongPress, 0, 1.25}];
    [builder beginParagraph:{} textStyle:fontStyle(font)];
    [builder appendText:@"Hello "];
    [builder pushSpan:{} interaction:_doubleTap];
    [builder appendText:@"dbl"];
    [builder pushSpan:{} interaction:_singleTap];
    [builder appendText:@"x"];
    [builder popSpan];
    [builder popSpan];
    [builder appendText:@" "];
    [builder pushSpan:{} interaction:_longPress];
    [builder appendText:@"hold"];
    [builder popSpan];
    [builder endParagraph];
    return [builder finish];
}

- (ATRTextDisplayView *)displayWithDocument:(ATRDocument *)document {
    ATRTextDisplayView *display = [[ATRTextDisplayView alloc] initWithFrame:CGRectMake(0, 0, 400, 200)];
    display.document = document;
    layoutNow(display);
    return display;
}

- (ATRHitView *)hitViewIn:(ATRTextDisplayView *)display containing:(NSArray<NSNumber *> *)interactions {
    for (ATRHitView *hitView in display.hitViews) {
        NSMutableSet *ids = [NSMutableSet set];

        for (ATRGestureBinding *binding in hitView.bindings) {
            [ids addObject:@(binding.interaction)];
        }

        if ([ids isEqualToSet:[NSSet setWithArray:interactions]]) {
            return hitView;
        }
    }

    return nil;
}

- (void)testHitViewsHostConfiguredRecognizers {
    ATRTextDisplayView *display = [self displayWithDocument:[self interactiveDocument]];

    XCTAssertEqual(display.hitViews.count, 3u);

    ATRHitView *nested = [self hitViewIn:display containing:@[@(_singleTap), @(_doubleTap)]];
    XCTAssertNotNil(nested);
    NSMutableSet *counts = [NSMutableSet set];

    for (ATRGestureBinding *binding in nested.bindings) {
        [counts addObject:@(tapCount(binding.recognizer))];
        XCTAssertTrue([nested.gestureRecognizers containsObject:binding.recognizer]);
    }

    XCTAssertEqualObjects(counts, ([NSSet setWithArray:@[@1, @2]]));

    ATRHitView *hold = [self hitViewIn:display containing:@[@(_longPress)]];
    ATRPlatformGestureRecognizer *press = hold.bindings.firstObject.recognizer;
#if TARGET_OS_OSX
    XCTAssertTrue([press isKindOfClass:NSPressGestureRecognizer.class]);
    XCTAssertEqual(((NSPressGestureRecognizer *)press).minimumPressDuration, 1.25);
#else
    XCTAssertTrue([press isKindOfClass:UILongPressGestureRecognizer.class]);
    XCTAssertEqual(((UILongPressGestureRecognizer *)press).minimumPressDuration, 1.25);
#endif
}

- (void)testTriggerReportsInteractionAndLocation {
    ATRTextDisplayView *display = [self displayWithDocument:[self interactiveDocument]];
    __block uint32_t received = ATRNoInteraction;
    __block CGPoint receivedLocation = CGPointZero;
    display.interactionHandler = ^(uint32_t interaction, CGPoint location) {
        received = interaction;
        receivedLocation = location;
    };

    ATRHitView *hold = [self hitViewIn:display containing:@[@(_longPress)]];
    [hold.bindings.firstObject triggerAtLocation:CGPointMake(3, 4)];

    XCTAssertEqual(received, _longPress);
    XCTAssertEqualWithAccuracy(receivedLocation.x, CGRectGetMinX(hold.frame) + 3, 0.001);
    XCTAssertEqualWithAccuracy(receivedLocation.y, CGRectGetMinY(hold.frame) + 4, 0.001);
}

- (void)testHitTestingUsesExactRegions {
    ATRPlatformView *host = [[ATRPlatformView alloc] initWithFrame:CGRectMake(0, 0, 400, 200)];
    ATRTextDisplayView *display = [self displayWithDocument:[self interactiveDocument]];
    [host addSubview:display];
    ATRHitView *hold = [self hitViewIn:display containing:@[@(_longPress)]];
    ATRHitView *nested = [self hitViewIn:display containing:@[@(_singleTap), @(_doubleTap)]];
    CGPoint inHold = CGPointMake(CGRectGetMidX(hold.frame), CGRectGetMidY(hold.frame));
    CGPoint inNested = CGPointMake(CGRectGetMidX(nested.frame), CGRectGetMidY(nested.frame));
    CGPoint inPlainText = CGPointMake(5, CGRectGetMidY(hold.frame));

#if TARGET_OS_OSX
    // AppKit hit-tests in superview coordinates, and the host is not flipped.
    XCTAssertEqual([display hitTest:[display convertPoint:inHold toView:host]], hold);
    XCTAssertEqual([display hitTest:[display convertPoint:inNested toView:host]], nested);
    XCTAssertEqual([display hitTest:[display convertPoint:inPlainText toView:host]], display);
#else
    XCTAssertEqual([display hitTest:inHold withEvent:nil], hold);
    XCTAssertEqual([display hitTest:inNested withEvent:nil], nested);
    XCTAssertEqual([display hitTest:inPlainText withEvent:nil], display);
#endif
}

- (void)testInjectedFactoryMakesTheBindings {
    ATRTextDisplayView *display = [self displayWithDocument:[self interactiveDocument]];
    CountingTapFactory *factory = [[CountingTapFactory alloc] init];
    ATRGestureRecognizerRegistry *registry = [ATRGestureRecognizerRegistry defaultRegistry];
    [registry registerFactory:factory forKind:ATRGestureKindTap];

    display.gestureRegistry = registry;

    // One binding per tap: the double tap on "dbl", and both taps on "x".
    XCTAssertEqual(factory.count, 3u);
    XCTAssertEqual(display.hitViews.count, 3u);
}

- (ATRDocument *)longDocument {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    int32_t font = [builder registerFont:[ATRPlatformFont systemFontOfSize:20]];

    for (int index = 0; index < 80; ++index) {
        [builder beginParagraph:{} textStyle:fontStyle(font)];
        [builder appendText:[NSString stringWithFormat:@"Paragraph %d", index]];
        [builder endParagraph];
    }

    return [builder finish];
}

- (void)testViewportTilesFollowTheEnclosingScrollView {
    ATRTextDisplayView *display = [[ATRTextDisplayView alloc] initWithFrame:CGRectZero];
    display.document = [self longDocument];
    display.viewportRenderingEnabled = YES;
    display.tileHeight = 100;
    CGSize size = [display sizeThatFitsWidth:320];
    display.frame = CGRectMake(0, 0, 320, size.height);
    XCTAssertGreaterThan(size.height, 1400);

    TestScrollView *scrollView = makeScrollView(display, size);
    TestWindow *window = makeWindow();
    addToWindow(scrollView, window);
    layoutNow(display);

    XCTAssertEqual(display.observedScrollView, scrollView);
    NSIndexSet *top = display.renderedTileIndexes;
    XCTAssertTrue([top containsIndex:0]);
    XCTAssertEqual(top.lastIndex, 3u);

#if TARGET_OS_OSX
    [scrollView.contentView scrollToPoint:NSMakePoint(0, 1000)];
    [scrollView reflectScrolledClipView:scrollView.contentView];
#else
    scrollView.contentOffset = CGPointMake(0, 1000);
#endif

    NSIndexSet *scrolled = display.renderedTileIndexes;
    XCTAssertFalse([scrolled containsIndex:0]);
    XCTAssertTrue([scrolled containsIndex:10]);
    XCTAssertTrue([scrolled containsIndex:12]);
    XCTAssertEqual(scrolled.firstIndex, 9u);
}

- (ATRTextDisplayView *)tiledDisplay {
    ATRTextDisplayView *display = [[ATRTextDisplayView alloc] initWithFrame:CGRectMake(0, 0, 320, 1600)];
    display.document = [self longDocument];
    display.viewportRenderingEnabled = YES;
    display.tileHeight = 100;
    return display;
}

- (void)testNoObservationOutsideAWindow {
    ATRTextDisplayView *display = [self tiledDisplay];
    TestScrollView *scrollView = makeScrollView(display, CGSizeMake(320, 1600));
    layoutNow(display);

    XCTAssertNil(display.observedScrollView);
    XCTAssertEqual(display.renderedTileIndexes.count, 0u);

    TestWindow *window = makeWindow();
    addToWindow(scrollView, window);
    layoutNow(display);

    XCTAssertEqual(display.observedScrollView, scrollView);
}

- (void)testLeavingTheWindowReleasesTheScrollView {
    ATRTextDisplayView *display = [self tiledDisplay];
    __weak TestScrollView *weakScrollView = nil;
    TestWindow *window = makeWindow();

    @autoreleasepool {
        TestScrollView *scrollView = makeScrollView(display, CGSizeMake(320, 1600));
        weakScrollView = scrollView;
        addToWindow(scrollView, window);
        layoutNow(display);
        XCTAssertEqual(display.observedScrollView, scrollView);

        [scrollView removeFromSuperview];
        XCTAssertNil(display.observedScrollView);
        [display removeFromSuperview];
    }

    // The display view outlives the scroll view without keeping it alive or
    // pointing at freed memory.
    XCTAssertNil(weakScrollView);
    layoutNow(display);
    display.viewportRenderingEnabled = NO;
}

- (void)testWholeSurfaceWithoutViewportRendering {
    ATRTextDisplayView *display = [self displayWithDocument:[self interactiveDocument]];

    XCTAssertEqual(display.renderedTileIndexes.count, 0u);
    NSUInteger drawnLayers = 0;

    for (CALayer *layer in display.layer.sublayers) {
        drawnLayers += layer.contents ? 1 : 0;
    }

    XCTAssertEqual(drawnLayers, 1u);
}

- (void)testAdaptiveAsyncImageRelayoutsWhenLoaded {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    ATRAttachmentDescriptor descriptor = {};
    descriptor.sizeKind = ATRAttachmentSizeKindAdaptive;
    descriptor.fields = ATRAttachmentFieldMaxWidth;
    descriptor.maxWidth = 80;
    descriptor.pipeline = ATRImagePipelineAsyncImage;
    [builder beginParagraph:{} textStyle:{}];
    [builder appendText:@"A"];
    uint32_t attachment = [builder appendAttachment:descriptor accessibilityLabel:nil];
    [builder endParagraph];
    ATRTextDisplayView *display = [self displayWithDocument:[builder finish]];
    __block NSUInteger sizeChanges = 0;
    display.contentSizeDidChangeHandler = ^{
        sizeChanges += 1;
    };

    XCTAssertEqual(CGRectGetWidth([display.textLayout attachmentFrameAtIndex:0].frame), 0);

    [display setImage:makeImage(CGSizeMake(200, 100)) forAttachment:attachment];
    layoutNow(display);

    CGRect frame = [display.textLayout attachmentFrameAtIndex:0].frame;
    XCTAssertTrue(CGSizeEqualToSize(frame.size, CGSizeMake(80, 40)));
    XCTAssertGreaterThan(sizeChanges, 0u);
}

- (void)testAsynchronousRenderingInstallsContentsLater {
    ATRTextDisplayView *display = [[ATRTextDisplayView alloc] initWithFrame:CGRectMake(0, 0, 400, 200)];
    display.rendersAsynchronously = YES;
    display.document = [self interactiveDocument];
    layoutNow(display);

    // Hit views add their own layers, so look for any drawn sublayer rather
    // than assuming an order.
    auto drawn = [&] {
        for (CALayer *layer in display.layer.sublayers) {
            if (layer.contents) {
                return YES;
            }
        }

        return NO;
    };
    XCTAssertFalse(drawn());
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];

    while (!drawn() && deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }

    XCTAssertTrue(drawn());
}

- (void)testLateAsynchronousResultNeverReplacesANewerOne {
    ATRTextDisplayView *display = [[ATRTextDisplayView alloc] initWithFrame:CGRectMake(0, 0, 400, 200)];
    display.rendersAsynchronously = YES;
    display.document = [self interactiveDocument];
    layoutNow(display);

    // Same width and content, so the same content generation: only the
    // per-layer request decides which bitmap wins.
    display.frame = CGRectMake(0, 0, 400, 80);
    layoutNow(display);

    auto surface = [&]() -> CALayer * {
        for (CALayer *layer in display.layer.sublayers) {
            if (CGRectGetWidth(layer.bounds) == 400) {
                return layer;
            }
        }

        return nil;
    };
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1];

    while (deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }

    CALayer *layer = surface();
    XCTAssertNotNil(layer.contents);
    CGImageRef image = (__bridge CGImageRef)layer.contents;
    XCTAssertEqual(CGImageGetHeight(image), static_cast<size_t>(std::ceil(80 * layer.contentsScale)));
}

- (void)testMatchingPreparedLayoutIsUsedAsIs {
    ATRDocument *document = [self interactiveDocument];
    ATRTextContainer container = {400, INFINITY, 0, ATRLineHeightModeTypographic};
    ATRTextLayout *prepared = [document layoutWithContainer:container truncationToken:@"…"];
    ATRTextDisplayView *display = [[ATRTextDisplayView alloc] initWithFrame:CGRectMake(0, 0, 400, 200)];
    [display setDocument:document layout:prepared];
    layoutNow(display);

    XCTAssertEqual(display.textLayout, prepared);
    XCTAssertEqual(display.hitViews.count, 3u);
}

- (void)testMismatchedPreparedLayoutIsReplaced {
    ATRDocument *document = [self interactiveDocument];
    ATRTextContainer narrow = {120, INFINITY, 0, ATRLineHeightModeTypographic};
    ATRTextContainer limited = {400, INFINITY, 1, ATRLineHeightModeTypographic};
    ATRTextDisplayView *display = [[ATRTextDisplayView alloc] initWithFrame:CGRectMake(0, 0, 400, 200)];

    for (ATRTextLayout *prepared in @[
             [document layoutWithContainer:narrow truncationToken:nil],
             [document layoutWithContainer:limited truncationToken:nil],
             [[self interactiveDocument] layoutWithContainer:narrow truncationToken:nil],
         ]) {
        [display setDocument:document layout:prepared];
        layoutNow(display);

        XCTAssertNotEqual(display.textLayout, prepared);
        XCTAssertEqual(display.textLayout.container.width, 400);
        XCTAssertEqual(display.textLayout.container.maximumNumberOfLines, 0u);
    }
}

// 60 paragraphs, each with one interactive word: a single tap, or a long
// press on every fifth paragraph.
- (ATRDocument *)longInteractiveDocument {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    int32_t font = [builder registerFont:[ATRPlatformFont systemFontOfSize:20]];

    for (int index = 0; index < 60; ++index) {
        ATRGesture gesture = index % 5 == 0 ? ATRGesture{ATRGestureKindLongPress, 0, 0.5} : ATRGesture{ATRGestureKindTap, 1, 0};
        uint32_t interaction = [builder registerInteractionWithGesture:gesture];
        [builder beginParagraph:{} textStyle:fontStyle(font)];
        [builder appendText:[NSString stringWithFormat:@"Paragraph %d ", index]];
        [builder pushSpan:{} interaction:interaction];
        [builder appendText:@"link"];
        [builder popSpan];
        [builder endParagraph];
    }

    return [builder finish];
}

- (void)testViewportHitViewsFollowAndAreReused {
    CountingTapFactory *factory = [[CountingTapFactory alloc] init];
    ATRGestureRecognizerRegistry *registry = [ATRGestureRecognizerRegistry defaultRegistry];
    [registry registerFactory:factory forKind:ATRGestureKindTap];

    ATRTextDisplayView *display = [[ATRTextDisplayView alloc] initWithFrame:CGRectZero];
    display.gestureRegistry = registry;
    display.document = [self longInteractiveDocument];
    display.viewportRenderingEnabled = YES;
    display.tileHeight = 100;
    CGSize size = [display sizeThatFitsWidth:320];
    display.frame = CGRectMake(0, 0, 320, size.height);
    TestScrollView *scrollView = makeScrollView(display, size);
    TestWindow *window = makeWindow();
    addToWindow(scrollView, window);
    layoutNow(display);

    // The scroll view shows 300 points; hit views cover 100 more above and
    // below.
    auto assertHitViewsNear = [&](CGFloat top) {
        XCTAssertGreaterThan(display.hitViews.count, 0u);
        XCTAssertLessThan(display.hitViews.count, 30u);

        for (ATRHitView *hitView in display.hitViews) {
            XCTAssertFalse(hitView.hidden);
            XCTAssertTrue(CGRectIntersectsRect(hitView.frame, CGRectMake(0, top - 100, 320, 500)));
        }
    };
    auto scrollTo = [&](CGFloat y) {
#if TARGET_OS_OSX
        [scrollView.contentView scrollToPoint:NSMakePoint(0, y)];
        [scrollView reflectScrolledClipView:scrollView.contentView];
#else
        scrollView.contentOffset = CGPointMake(0, y);
#endif
    };
    auto tapViews = [&] {
        NSUInteger count = 0;

        for (ATRHitView *hitView in display.hitViews) {
            count += hitView.bindings.firstObject.gesture.kind == ATRGestureKindTap ? 1 : 0;
        }

        return count;
    };

    assertHitViewsNear(0);
    NSUInteger topTaps = tapViews();
    XCTAssertEqual(factory.count, topTaps);

    // No set is visible in both places, so every tap hit view from the top
    // is reused and only the extra ones are created.
    scrollTo(1000);
    assertHitViewsNear(1000);
    NSUInteger scrolledTaps = tapViews();
    XCTAssertEqual(factory.count, MAX(topTaps, scrolledTaps));

    scrollTo(0);
    assertHitViewsNear(0);
    XCTAssertEqual(factory.count, MAX(topTaps, scrolledTaps));
    // Pooled hit views stay as hidden subviews instead of being recreated.
    NSUInteger subviewHitViews = 0;

    for (ATRPlatformView *subview in display.subviews) {
        subviewHitViews += [subview isKindOfClass:ATRHitView.class] ? 1 : 0;
    }

    XCTAssertEqual(display.reusableHitViewCount + display.hitViews.count, subviewHitViews);
    XCTAssertGreaterThan(display.reusableHitViewCount, 0u);

    scrollTo(1000);

    __block uint32_t reported = UINT32_MAX;
    display.interactionHandler = ^(uint32_t interaction, CGPoint location) {
        reported = interaction;
    };

    for (ATRHitView *hitView in display.hitViews) {
        NSArray<NSNumber *> *expected = [display.textLayout interactionsInSet:hitView.interactionSet];
        XCTAssertEqual(hitView.bindings.count, expected.count);
        [hitView.bindings.firstObject triggerAtLocation:CGPointZero];
        XCTAssertEqual(reported, expected.firstObject.unsignedIntValue);
    }

    display.viewportRenderingEnabled = NO;
    layoutNow(display);
    XCTAssertEqual(display.hitViews.count, 60u);
}

- (ATRDocument *)plainDocument:(NSString *)text {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    int32_t font = [builder registerFont:[ATRPlatformFont systemFontOfSize:20]];
    [builder beginParagraph:{} textStyle:fontStyle(font)];
    [builder appendText:text];
    [builder endParagraph];
    return [builder finish];
}

- (void)testSettingsRelayoutOnlyWhenTheyChange {
    NSString *text = @"The quick brown fox jumps over the lazy dog and keeps running across the field.";
    ATRTextDisplayView *display = [self displayWithDocument:[self plainDocument:text]];
    ATRTextLayout *initial = display.textLayout;
    XCTAssertNotNil(initial);

    display.maximumNumberOfLines = 0;
    display.truncationToken = nil;
    display.lineHeightMode = ATRLineHeightModeTypographic;
    layoutNow(display);
    XCTAssertEqual(display.textLayout, initial);

    display.maximumNumberOfLines = 1;
    XCTAssertNil(display.textLayout);
    layoutNow(display);
    XCTAssertEqual(display.textLayout.container.maximumNumberOfLines, 1u);
    XCTAssertTrue(display.textLayout.truncated);

    ATRTextLayout *limited = display.textLayout;
    display.truncationToken = @"…";
    layoutNow(display);
    // Nil and U+2026 are the same token.
    XCTAssertEqual(display.textLayout, limited);

    display.truncationToken = @"...";
    layoutNow(display);
    XCTAssertEqualObjects(display.textLayout.truncationToken, @"...");

    display.lineHeightMode = ATRLineHeightModeGlyphBounds;
    layoutNow(display);
    XCTAssertEqual(display.textLayout.container.lineHeightMode, ATRLineHeightModeGlyphBounds);
}

- (void)testResizingRelayoutsForTheNewWidth {
    NSString *text = @"The quick brown fox jumps over the lazy dog and keeps running across the field.";
    ATRTextDisplayView *display = [self displayWithDocument:[self plainDocument:text]];
    NSUInteger wideLines = display.textLayout.lineCount;

    display.frame = CGRectMake(0, 0, 120, 200);
    layoutNow(display);

    XCTAssertEqual(display.textLayout.container.width, 120);
    XCTAssertGreaterThan(display.textLayout.lineCount, wideLines);

    display.frame = CGRectMake(0, 0, 0, 200);
    layoutNow(display);
    XCTAssertNil(display.textLayout);
}

- (void)testRemovingTheDocumentClearsEverything {
    ATRTextDisplayView *display = [self displayWithDocument:[self interactiveDocument]];
    XCTAssertEqual(display.hitViews.count, 3u);

    display.document = nil;
    layoutNow(display);

    XCTAssertNil(display.textLayout);
    XCTAssertEqual(display.hitViews.count, 0u);
    XCTAssertTrue(CGSizeEqualToSize([display sizeThatFitsWidth:400], CGSizeZero));
}

- (void)testSettingTheSameDocumentKeepsTheLayout {
    ATRDocument *document = [self interactiveDocument];
    ATRTextDisplayView *display = [self displayWithDocument:document];
    ATRTextLayout *layout = display.textLayout;
    NSArray<ATRHitView *> *hitViews = display.hitViews;

    display.document = document;
    layoutNow(display);

    XCTAssertEqual(display.textLayout, layout);
    XCTAssertEqualObjects(display.hitViews, hitViews);
}

- (void)testALayoutOfAnotherDocumentIsIgnored {
    ATRDocument *first = [self plainDocument:@"First"];
    ATRDocument *second = [self plainDocument:@"Second, which is longer"];
    ATRTextLayout *foreign = [first layoutWithContainer:{400, INFINITY, 0, ATRLineHeightModeTypographic}
                                        truncationToken:nil];
    ATRTextDisplayView *display = [[ATRTextDisplayView alloc] initWithFrame:CGRectMake(0, 0, 400, 200)];

    [display setDocument:second layout:foreign];
    layoutNow(display);

    XCTAssertNotEqual(display.textLayout, foreign);
    XCTAssertEqual(display.textLayout.document, second);
}

- (void)testMeasuringRoundsUpAndLeavesTheLayoutAlone {
    ATRTextDisplayView *display = [self displayWithDocument:[self plainDocument:@"Measure me"]];
    ATRTextLayout *installed = display.textLayout;
    CGSize narrow = [display sizeThatFitsWidth:50];
    CGSize wide = [display sizeThatFitsWidth:400];

    XCTAssertEqual(narrow.width, std::ceil(narrow.width));
    XCTAssertEqual(narrow.height, std::ceil(narrow.height));
    XCTAssertGreaterThan(narrow.height, wide.height);
    XCTAssertEqual(wide.width, std::ceil(installed.size.width));
    XCTAssertEqual(display.textLayout, installed);

    XCTAssertTrue(CGSizeEqualToSize([display sizeThatFitsWidth:0], CGSizeZero));
    XCTAssertTrue(CGSizeEqualToSize([display sizeThatFitsWidth:-5], CGSizeZero));
    XCTAssertTrue(CGSizeEqualToSize([display sizeThatFitsWidth:NAN], CGSizeZero));
    XCTAssertTrue(std::isfinite([display sizeThatFitsWidth:INFINITY].width));
}

- (void)testIntrinsicSizeNeedsAWidth {
    ATRTextDisplayView *display = [[ATRTextDisplayView alloc] initWithFrame:CGRectZero];
    display.document = [self plainDocument:@"Intrinsic"];
#if TARGET_OS_OSX
    XCTAssertEqual(display.intrinsicContentSize.height, NSViewNoIntrinsicMetric);
#else
    XCTAssertEqual(display.intrinsicContentSize.height, UIViewNoIntrinsicMetric);
#endif

    display.frame = CGRectMake(0, 0, 300, 10);
    CGSize size = display.intrinsicContentSize;
    XCTAssertGreaterThan(size.height, 0);
    XCTAssertTrue(CGSizeEqualToSize(size, [display sizeThatFitsWidth:300]));
}

- (void)testImagesForSpacersFixedImagesAndUnknownIDs {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    ATRAttachmentDescriptor fixed = {};
    fixed.sizeKind = ATRAttachmentSizeKindFixed;
    fixed.width = 20;
    fixed.height = 20;
    ATRAttachmentDescriptor spacer = fixed;
    spacer.kind = ATRAttachmentKindSpacer;
    [builder beginParagraph:{} textStyle:{}];
    uint32_t image = [builder appendAttachment:fixed accessibilityLabel:nil];
    uint32_t gap = [builder appendAttachment:spacer accessibilityLabel:nil];
    [builder endParagraph];
    ATRTextDisplayView *display = [self displayWithDocument:[builder finish]];
    ATRTextLayout *layout = display.textLayout;

    [display setImage:makeImage(CGSizeMake(200, 100)) forAttachment:image];
    [display setImage:makeImage(CGSizeMake(5, 5)) forAttachment:gap];
    [display setImage:makeImage(CGSizeMake(5, 5)) forAttachment:99];
    [display setImage:nil forAttachment:image];
    layoutNow(display);

    // None of these change the layout: a fixed image only redraws.
    XCTAssertEqual(display.textLayout, layout);
}

- (void)testRemovingAnAsyncImageShrinksItBack {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    ATRAttachmentDescriptor descriptor = {};
    descriptor.sizeKind = ATRAttachmentSizeKindAdaptive;
    descriptor.fields = ATRAttachmentFieldMaxWidth;
    descriptor.maxWidth = 80;
    descriptor.pipeline = ATRImagePipelineAsyncImage;
    [builder beginParagraph:{} textStyle:{}];
    uint32_t attachment = [builder appendAttachment:descriptor accessibilityLabel:nil];
    [builder endParagraph];
    ATRTextDisplayView *display = [self displayWithDocument:[builder finish]];

    [display setImage:makeImage(CGSizeMake(200, 100)) forAttachment:attachment];
    layoutNow(display);
    XCTAssertEqual(CGRectGetWidth([display.textLayout attachmentFrameAtIndex:0].frame), 80);

    [display setImage:nil forAttachment:attachment];
    layoutNow(display);
    XCTAssertEqual(CGRectGetWidth([display.textLayout attachmentFrameAtIndex:0].frame), 0);
}

- (void)testImagesDoNotCarryOverToANewDocument {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    ATRAttachmentDescriptor descriptor = {};
    descriptor.sizeKind = ATRAttachmentSizeKindAdaptive;
    descriptor.fields = ATRAttachmentFieldMaxWidth;
    descriptor.maxWidth = 80;
    descriptor.pipeline = ATRImagePipelineAsyncImage;
    [builder beginParagraph:{} textStyle:{}];
    [builder appendAttachment:descriptor accessibilityLabel:nil];
    [builder endParagraph];
    ATRDocument *document = [builder finish];
    ATRTextDisplayView *display = [self displayWithDocument:document];
    [display setImage:makeImage(CGSizeMake(200, 100)) forAttachment:0];
    layoutNow(display);

    // An equal but distinct document starts without loaded images.
    ATRDocumentBuilder *again = [[ATRDocumentBuilder alloc] init];
    [again beginParagraph:{} textStyle:{}];
    [again appendAttachment:descriptor accessibilityLabel:nil];
    [again endParagraph];
    display.document = [again finish];
    layoutNow(display);

    XCTAssertEqual(CGRectGetWidth([display.textLayout attachmentFrameAtIndex:0].frame), 0);
}

- (void)testReplacingTheRegistryRebuildsHitViews {
    ATRTextDisplayView *display = [self displayWithDocument:[self interactiveDocument]];
    NSArray<ATRHitView *> *before = display.hitViews;
    CountingTapFactory *factory = [[CountingTapFactory alloc] init];
    ATRGestureRecognizerRegistry *registry = [ATRGestureRecognizerRegistry defaultRegistry];
    [registry registerFactory:factory forKind:ATRGestureKindTap];

    display.gestureRegistry = registry;
    layoutNow(display);

    XCTAssertEqual(display.hitViews.count, before.count);
    XCTAssertGreaterThan(factory.count, 0u);

    for (ATRHitView *hitView in display.hitViews) {
        for (ATRGestureBinding *binding in hitView.bindings) {
            XCTAssertTrue([hitView.gestureRecognizers containsObject:binding.recognizer]);
        }
    }
}

@end
