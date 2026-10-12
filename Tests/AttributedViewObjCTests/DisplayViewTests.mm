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

@end
