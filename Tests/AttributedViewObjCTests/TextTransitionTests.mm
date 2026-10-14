// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import <Metal/Metal.h>
#import <XCTest/XCTest.h>

#import "ATRDocumentBuilder.h"
#import "ATRTextDisplayView.h"

#include <string>
#include <vector>

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

// One atom per character, keyed by the character; digits, and "." or ","
// next to one, are numeric like the engine's.
std::vector<ATRGlyphAtom> atoms(const std::string &text) {
    std::vector<ATRGlyphAtom> result;

    for (size_t index = 0; index < text.size(); ++index) {
        char character = text[index];
        auto digit = [&](size_t at) { return at < text.size() && text[at] >= '0' && text[at] <= '9'; };
        ATRGlyphAtom atom = {};
        atom.font = 1;
        atom.glyph = static_cast<uint32_t>(character);
        atom.numeric = digit(index)
            || ((character == '.' || character == ',') && ((index > 0 && digit(index - 1)) || digit(index + 1)));
        result.push_back(atom);
    }

    return result;
}

std::pair<NSUInteger, NSUInteger> kept(const std::string &from, const std::string &to) {
    auto old = atoms(from);
    auto incoming = atoms(to);
    NSUInteger prefix = 0;
    NSUInteger suffix = 0;
    [ATRNumericTextTransition keptCountsFrom:old.data()
                                       count:old.size()
                                          to:incoming.data()
                                       count:incoming.size()
                                      prefix:&prefix
                                      suffix:&suffix];
    return {prefix, suffix};
}

} // namespace

// Records what the host tells it and finishes when told to.
@interface RecordingTransition : NSObject <ATRTextTransitionEffect>
@property (nonatomic) BOOL refusesToBegin;
@property (nonatomic, weak) ATRPlatformView *host;
@property (nonatomic, copy) void (^completion)(void);
@property (nonatomic) NSUInteger beginAtomCount;
@property (nonatomic, strong) NSMutableArray<NSString *> *calls;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *atomCounts;
@end

@implementation RecordingTransition

- (instancetype)init {
    self = [super init];
    _calls = [NSMutableArray array];
    _atomCounts = [NSMutableArray array];
    return self;
}

- (BOOL)beginOnHost:(ATRPlatformView *)host snapshot:(ATRGlyphSnapshot *)snapshot completion:(void (^)(void))completion {
    if (self.refusesToBegin) {
        return NO;
    }

    self.host = host;
    self.completion = completion;
    self.beginAtomCount = snapshot.atomCount;
    [self.calls addObject:@"begin"];
    return YES;
}

- (void)transitionToSnapshot:(ATRGlyphSnapshot *)snapshot {
    [self.calls addObject:@"transition"];
    [self.atomCounts addObject:@(snapshot.atomCount)];
}

- (BOOL)relayoutWithSnapshot:(ATRGlyphSnapshot *)snapshot {
    [self.calls addObject:@"relayout"];
    [self.atomCounts addObject:@(snapshot.atomCount)];
    return YES;
}

- (void)cancel {
    [self.calls addObject:@"cancel"];
}

@end

@interface TextTransitionTests : XCTestCase
@end

@implementation TextTransitionTests {
#if TARGET_OS_OSX
    NSWindow *_window;
#else
    UIWindow *_window;
#endif
}

- (void)setUp {
#if TARGET_OS_OSX
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 320, 600)
                                          styleMask:NSWindowStyleMaskBorderless
                                            backing:NSBackingStoreBuffered
                                              defer:YES];
    _window.releasedWhenClosed = NO;
#else
    _window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 320, 600)];
    _window.hidden = NO;
#endif
}

- (void)tearDown {
#if TARGET_OS_OSX
    [_window close];
#else
    _window.hidden = YES;
#endif
    _window = nil;
}

- (ATRDocument *)document:(NSString *)text {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    int32_t font = [builder registerFont:[ATRPlatformFont systemFontOfSize:24]];
    [builder beginParagraph:{} textStyle:fontStyle(font)];
    [builder appendText:text];
    [builder endParagraph];
    return [builder finish];
}

- (ATRTextDisplayView *)displayInWindow:(NSString *)text {
    ATRTextDisplayView *display = [[ATRTextDisplayView alloc] initWithFrame:CGRectMake(0, 0, 300, 60)];
    display.document = [self document:text];
#if TARGET_OS_OSX
    [_window.contentView addSubview:display];
#else
    [_window addSubview:display];
#endif
    layoutNow(display);
    return display;
}

- (void)setText:(NSString *)text
              on:(ATRTextDisplayView *)display
          effect:(id<ATRTextTransitionEffect>)effect
        outcomes:(NSMutableArray<NSNumber *> *)outcomes {
    [display setDocument:[self document:text]
                  layout:nil
              transition:^id<ATRTextTransitionEffect>(id<ATRTextTransitionEffect> running) {
                  return running ?: effect;
              }
              completion:^(ATRTextTransitionOutcome outcome) {
                  [outcomes addObject:@(outcome)];
              }];
}

- (BOOL)ownDrawingHidden:(ATRTextDisplayView *)display {
    for (CALayer *layer in display.layer.sublayers) {
        if (layer.hidden) {
            return YES;
        }
    }

    return NO;
}

// MARK: Kept glyphs

- (void)testKeptCountsKeepCommonStartAndEnd {
    XCTAssertEqual(kept("Hello world", "Hello there"), std::make_pair(NSUInteger(6), NSUInteger(0)));
    XCTAssertEqual(kept("$9 left", "$10 left"), std::make_pair(NSUInteger(1), NSUInteger(5)));
    XCTAssertEqual(kept("abc", "abc"), std::make_pair(NSUInteger(3), NSUInteger(0)));
    XCTAssertEqual(kept("", "42"), std::make_pair(NSUInteger(0), NSUInteger(0)));
}

- (void)testNumbersRollLikeAnOdometer {
    // "29" changes, so the 9 after the changed digit rolls with it.
    XCTAssertEqual(kept("129", "139"), std::make_pair(NSUInteger(1), NSUInteger(0)));
    XCTAssertEqual(kept("1,234.50", "1,284.50"), std::make_pair(NSUInteger(3), NSUInteger(0)));
    // Text after the number stays.
    XCTAssertEqual(kept("129 pts", "139 pts"), std::make_pair(NSUInteger(1), NSUInteger(4)));
}

// MARK: Host

- (void)testEffectGetsOldContentThenNewContentAtLayout {
    ATRTextDisplayView *display = [self displayInWindow:@"12"];
    RecordingTransition *effect = [[RecordingTransition alloc] init];
    NSMutableArray<NSNumber *> *outcomes = [NSMutableArray array];

    [self setText:@"345" on:display effect:effect outcomes:outcomes];

    XCTAssertEqual(effect.beginAtomCount, 2u);
    XCTAssertEqualObjects(effect.calls, @[@"begin"]);
    XCTAssertEqual(display.transitionEffect, effect);
    XCTAssertTrue([self ownDrawingHidden:display]);

    layoutNow(display);

    XCTAssertEqualObjects(effect.calls, (@[@"begin", @"transition"]));
    XCTAssertEqualObjects(effect.atomCounts, @[@3]);

    effect.completion();

    XCTAssertEqualObjects(effect.calls, (@[@"begin", @"transition", @"cancel"]));
    XCTAssertEqualObjects(outcomes, @[@(ATRTextTransitionOutcomeFinished)]);
    XCTAssertNil(display.transitionEffect);
    XCTAssertFalse([self ownDrawingHidden:display]);
}

- (void)testLaterTransitionSupersedesAndCarriesOn {
    ATRTextDisplayView *display = [self displayInWindow:@"1"];
    RecordingTransition *effect = [[RecordingTransition alloc] init];
    NSMutableArray<NSNumber *> *first = [NSMutableArray array];
    NSMutableArray<NSNumber *> *second = [NSMutableArray array];

    [self setText:@"2" on:display effect:effect outcomes:first];
    layoutNow(display);
    [self setText:@"3" on:display effect:[[RecordingTransition alloc] init] outcomes:second];

    XCTAssertEqualObjects(first, @[@(ATRTextTransitionOutcomeSuperseded)]);
    XCTAssertEqual(display.transitionEffect, effect);

    layoutNow(display);
    effect.completion();

    XCTAssertEqualObjects(effect.calls, (@[@"begin", @"transition", @"transition", @"cancel"]));
    XCTAssertEqualObjects(second, @[@(ATRTextTransitionOutcomeFinished)]);
}

- (void)testPlainAssignmentInterrupts {
    ATRTextDisplayView *display = [self displayInWindow:@"1"];
    RecordingTransition *effect = [[RecordingTransition alloc] init];
    NSMutableArray<NSNumber *> *outcomes = [NSMutableArray array];

    [self setText:@"2" on:display effect:effect outcomes:outcomes];
    layoutNow(display);
    display.document = [self document:@"3"];

    XCTAssertEqualObjects(outcomes, @[@(ATRTextTransitionOutcomeInterrupted)]);
    XCTAssertEqualObjects(effect.calls.lastObject, @"cancel");
    XCTAssertFalse([self ownDrawingHidden:display]);
}

- (void)testRelayoutWhileRunningReachesTheEffect {
    ATRTextDisplayView *display = [self displayInWindow:@"1 2 3"];
    RecordingTransition *effect = [[RecordingTransition alloc] init];

    [self setText:@"4 5 6" on:display effect:effect outcomes:[NSMutableArray array]];
    layoutNow(display);
    display.frame = CGRectMake(0, 0, 200, 60);
    layoutNow(display);

    XCTAssertEqualObjects(effect.calls, (@[@"begin", @"transition", @"relayout"]));
}

- (void)testSkipsWithoutWindowOrWithViewportRendering {
    ATRTextDisplayView *detached = [[ATRTextDisplayView alloc] initWithFrame:CGRectMake(0, 0, 300, 60)];
    NSMutableArray<NSNumber *> *outcomes = [NSMutableArray array];
    [self setText:@"1" on:detached effect:[[RecordingTransition alloc] init] outcomes:outcomes];

    ATRTextDisplayView *tiled = [self displayInWindow:@"1"];
    tiled.viewportRenderingEnabled = YES;
    [self setText:@"2" on:tiled effect:[[RecordingTransition alloc] init] outcomes:outcomes];

    RecordingTransition *refusing = [[RecordingTransition alloc] init];
    refusing.refusesToBegin = YES;
    [self setText:@"3" on:[self displayInWindow:@"2"] effect:refusing outcomes:outcomes];

    XCTAssertEqualObjects(outcomes, (@[
        @(ATRTextTransitionOutcomeSkipped),
        @(ATRTextTransitionOutcomeSkipped),
        @(ATRTextTransitionOutcomeSkipped),
    ]));
}

- (void)testLeavingTheWindowInterrupts {
    ATRTextDisplayView *display = [self displayInWindow:@"1"];
    NSMutableArray<NSNumber *> *outcomes = [NSMutableArray array];

    [self setText:@"2" on:display effect:[[RecordingTransition alloc] init] outcomes:outcomes];
    [display removeFromSuperview];

    XCTAssertEqualObjects(outcomes, @[@(ATRTextTransitionOutcomeInterrupted)]);
}

- (void)testAsynchronousDrawingFinishesOnceTheBitmapLands {
    ATRTextDisplayView *display = [self displayInWindow:@"1"];
    display.rendersAsynchronously = YES;
    RecordingTransition *effect = [[RecordingTransition alloc] init];
    NSMutableArray<NSNumber *> *outcomes = [NSMutableArray array];

    [self setText:@"2" on:display effect:effect outcomes:outcomes];
    layoutNow(display);
    effect.completion();

    XCTAssertEqualObjects(outcomes, @[]);

    for (int attempt = 0; attempt < 50 && outcomes.count == 0; ++attempt) {
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }

    XCTAssertEqualObjects(outcomes, @[@(ATRTextTransitionOutcomeFinished)]);
}

// MARK: Numeric text

- (void)testNumericTextRunsToItsEndOnIOS {
    ATRTextDisplayView *display = [self displayInWindow:@"$99"];
    NSMutableArray<NSNumber *> *outcomes = [NSMutableArray array];

    [self setText:@"$100" on:display effect:[[ATRNumericTextTransition alloc] init] outcomes:outcomes];
    layoutNow(display);

#if TARGET_OS_OSX
    XCTAssertEqualObjects(outcomes, @[@(ATRTextTransitionOutcomeSkipped)]);
#else
    if (!MTLCreateSystemDefaultDevice()) {
        XCTAssertEqualObjects(outcomes, @[@(ATRTextTransitionOutcomeSkipped)]);
        return;
    }

    XCTAssertEqualObjects(outcomes, @[]);
    XCTAssertTrue([display.transitionEffect isKindOfClass:ATRNumericTextTransition.class]);

    for (int attempt = 0; attempt < 300 && outcomes.count == 0; ++attempt) {
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }

    XCTAssertEqualObjects(outcomes, @[@(ATRTextTransitionOutcomeFinished)]);
    XCTAssertNil(display.transitionEffect);
    XCTAssertEqual(display.subviews.count, display.hitViews.count);
#endif
}

- (void)testPrewarmBuildsOnce {
    ATRTextTransitionPrewarmResult first = [ATRNumericTextTransition prewarm];
    ATRTextTransitionPrewarmResult second = [ATRNumericTextTransition prewarm];

#if TARGET_OS_OSX
    XCTAssertTrue(first == ATRTextTransitionPrewarmResultFailed || first == ATRTextTransitionPrewarmResultAlreadyFailed);
    XCTAssertEqual(second, ATRTextTransitionPrewarmResultAlreadyFailed);
#else
    XCTAssertTrue(first == ATRTextTransitionPrewarmResultSucceeded || first == ATRTextTransitionPrewarmResultAlreadyPrewarmed);
    XCTAssertEqual(second, ATRTextTransitionPrewarmResultAlreadyPrewarmed);
#endif
}

@end
