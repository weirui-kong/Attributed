// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRTextTransition.h"

#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <mutex>
#include <vector>

#if !__has_feature(objc_arc)
#error "AttributedViewObjC must be compiled with ARC."
#endif

// Building the pipeline takes milliseconds, too long to repeat for every
// transition, so one pipeline serves them all.
@interface ATRNumericTextRenderer : NSObject
@property (nonatomic, strong, nonnull) id<MTLDevice> device;
@property (nonatomic, strong, nonnull) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong, nonnull) id<MTLRenderPipelineState> pipeline;
@property (nonatomic, strong, nonnull) id<MTLSamplerState> sampler;
@end

@implementation ATRNumericTextRenderer
@end

namespace {

ATRNumericTextRenderer *makeRenderer() {
#if TARGET_OS_OSX
    return nil;
#else
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    id<MTLCommandQueue> queue = [device newCommandQueue];
    // Compiled into the target's resource bundle at build time; only the
    // pipeline still has to be built here.
    id<MTLLibrary> library = queue ? [device newDefaultLibraryWithBundle:SWIFTPM_MODULE_BUNDLE error:nil] : nil;

    if (!library) {
        return nil;
    }

    MTLRenderPipelineDescriptor *descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = [library newFunctionWithName:@"atrNumericTextVertex"];
    descriptor.fragmentFunction = [library newFunctionWithName:@"atrNumericTextFragment"];
    MTLRenderPipelineColorAttachmentDescriptor *color = descriptor.colorAttachments[0];
    color.pixelFormat = MTLPixelFormatBGRA8Unorm;
    color.blendingEnabled = YES;
    // Tiles hold premultiplied alpha.
    color.sourceRGBBlendFactor = MTLBlendFactorOne;
    color.sourceAlphaBlendFactor = MTLBlendFactorOne;
    color.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    color.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    MTLSamplerDescriptor *samplerDescriptor = [[MTLSamplerDescriptor alloc] init];
    samplerDescriptor.minFilter = MTLSamplerMinMagFilterLinear;
    samplerDescriptor.magFilter = MTLSamplerMinMagFilterLinear;
    samplerDescriptor.mipFilter = MTLSamplerMipFilterLinear;

    id<MTLRenderPipelineState> pipeline = [device newRenderPipelineStateWithDescriptor:descriptor error:nil];
    id<MTLSamplerState> sampler = [device newSamplerStateWithDescriptor:samplerDescriptor];

    if (!pipeline || !sampler) {
        return nil;
    }

    ATRNumericTextRenderer *renderer = [[ATRNumericTextRenderer alloc] init];
    renderer.device = device;
    renderer.commandQueue = queue;
    renderer.pipeline = pipeline;
    renderer.sampler = sampler;
    return renderer;
#endif
}

// A first use builds on its own thread without waiting for a build running
// elsewhere; whichever result is stored first is the one everybody gets from
// then on, including a failure. Prewarming stays out of the way of a build
// already running.
class RendererStore {
public:
    ATRNumericTextRenderer *get() {
        {
            std::lock_guard<std::mutex> lock(mutex_);

            if (stored_) {
                return value_;
            }

            ++inFlight_;
        }

        return build().first;
    }

    ATRTextTransitionPrewarmResult prewarm() {
        {
            std::lock_guard<std::mutex> lock(mutex_);

            if (stored_) {
                return value_ ? ATRTextTransitionPrewarmResultAlreadyPrewarmed
                              : ATRTextTransitionPrewarmResultAlreadyFailed;
            }

            if (inFlight_ > 0) {
                return ATRTextTransitionPrewarmResultAlreadyInProgress;
            }

            ++inFlight_;
        }

        auto [value, kept] = build();

        if (!kept) {
            return ATRTextTransitionPrewarmResultSuperseded;
        }

        return value ? ATRTextTransitionPrewarmResultSucceeded : ATRTextTransitionPrewarmResultFailed;
    }

private:
    std::mutex mutex_;
    bool stored_ = false;
    ATRNumericTextRenderer *value_ = nil;
    int inFlight_ = 0;

    // Entered with this call already counted in `inFlight_`.
    std::pair<ATRNumericTextRenderer *, bool> build() {
        ATRNumericTextRenderer *built = makeRenderer();
        std::lock_guard<std::mutex> lock(mutex_);
        --inFlight_;

        if (stored_) {
            return {value_, false};
        }

        stored_ = true;
        value_ = built;
        return {built, true};
    }
};

RendererStore &rendererStore() {
    static RendererStore *store = new RendererStore();
    return *store;
}

void keptCounts(const ATRGlyphAtom *from, size_t fromCount, const ATRGlyphAtom *to, size_t toCount, size_t &prefix, size_t &suffix) {
    auto same = [](const ATRGlyphAtom &a, const ATRGlyphAtom &b) { return a.font == b.font && a.glyph == b.glyph; };
    size_t shorter = std::min(fromCount, toCount);
    prefix = 0;

    while (prefix < shorter && same(from[prefix], to[prefix])) {
        ++prefix;
    }

    suffix = 0;

    while (suffix < shorter - prefix && same(from[fromCount - 1 - suffix], to[toCount - 1 - suffix])) {
        ++suffix;
    }

    // An odometer: once a digit changes, every digit after it in the same
    // number rolls too, changed or not.
    bool changeEndsInNumber = (prefix < fromCount - suffix && from[fromCount - suffix - 1].numeric)
        || (prefix < toCount - suffix && to[toCount - suffix - 1].numeric);

    if (changeEndsInNumber) {
        while (suffix > 0 && to[toCount - suffix].numeric) {
            --suffix;
        }
    }
}

} // namespace

#if !TARGET_OS_OSX

namespace {

struct Spring {
    double mass;
    double stiffness;
    double damping;

    double omega() const { return std::sqrt(stiffness / mass); }
    double zeta() const { return damping / (2 * std::sqrt(stiffness * mass)); }

    double settlingDuration() const {
        return 10 / (std::min(zeta(), 1.0) * omega());
    }

    double value(double time) const {
        if (time <= 0) {
            return 0;
        }

        double w = omega();
        double z = zeta();

        if (z >= 1) {
            return 1 - std::exp(-w * time) * (1 + w * time);
        }

        double damped = w * std::sqrt(1 - z * z);
        return 1 - std::exp(-z * w * time) * (std::cos(damped * time) + z * w / damped * std::sin(damped * time));
    }
};

// The values SwiftUI hands RenderBox for .numericText() on iOS 26. Blur and
// offset are relative to the glyph's ink height, matched by eye; the stagger
// was measured from screen recordings.
struct Configuration {
    double scale = 51.0 / 128;
    double relativeBlur = 0.25;
    double relativeOffset = 19.0 / 32;
    Spring presence = {1, 344, 37};
    Spring shift = {2, 470, 34};
    double staggerStep = 0.15;
    double maxStagger = 0.2;
};

// For positions, an end that rides is in host coordinates and moves with the
// host wherever layout takes it; one that does not is a fixed place in the
// anchor's coordinates. Where a glyph comes from is usually fixed, where it
// goes rides.
struct Track {
    double from = 0;
    double to = 0;
    CFTimeInterval start = 0;
    bool fromRides = false;
    bool toRides = false;

    static Track resting(double value) {
        return {value, value, 0, true, true};
    }
};

struct Glyph {
    ATRGlyphAtom atom;
    // Nil for atoms without area; whitespace still takes part in the diff.
    id<MTLTexture> texture;
    Track x;
    Track y;
    Track presence;
    Track shift;
    bool removing = false;
};

// Transparent pixels around every tile, so blurred mip levels never reach
// the texture edge.
constexpr int kTextureBorder = 8;
constexpr NSUInteger kFloatsPerVertex = 6;
constexpr NSUInteger kVertexBufferCount = 3;

// `origin` is the host's origin in the anchor's coordinates along the
// track's axis; only positions need it.
double valueOf(const Track &track, const Spring &spring, CFTimeInterval time, double origin = 0) {
    double from = track.from + (track.fromRides ? origin : 0);
    double to = track.to + (track.toRides ? origin : 0);
    return from + (to - from) * spring.value(time - track.start);
}

// Cuts tiles out of one snapshot and generates their mipmaps in a single
// command buffer.
class TextureBatch {
public:
    TextureBatch(ATRNumericTextRenderer *renderer, ATRGlyphSnapshot *snapshot)
        : renderer_(renderer), snapshot_(snapshot) {}

    ~TextureBatch() {
        [blit_ endEncoding];
        [commandBuffer_ commit];
    }

    id<MTLTexture> make(const ATRGlyphAtom &atom) {
        CGFloat scale = snapshot_.scale;
        CGRect frame = snapshot_.frame;
        auto left = static_cast<long>(std::lround((CGRectGetMinX(atom.tile) - CGRectGetMinX(frame)) * scale));
        auto top = static_cast<long>(std::lround((CGRectGetMinY(atom.tile) - CGRectGetMinY(frame)) * scale));
        auto width = static_cast<long>(std::lround(CGRectGetWidth(atom.tile) * scale));
        auto height = static_cast<long>(std::lround(CGRectGetHeight(atom.tile) * scale));
        const auto *pixels = static_cast<const uint8_t *>(snapshot_.pixels);

        if (!renderer_ || !pixels || width <= 0 || height <= 0 || left < 0 || top < 0
            || left + width > static_cast<long>(snapshot_.pixelWidth)
            || top + height > static_cast<long>(snapshot_.pixelHeight)) {
            return nil;
        }

        long rowBytes = (width + kTextureBorder * 2) * 4;
        std::vector<uint8_t> bordered(static_cast<size_t>(rowBytes * (height + kTextureBorder * 2)), 0);

        for (long row = 0; row < height; ++row) {
            std::copy_n(
                pixels + (top + row) * snapshot_.bytesPerRow + left * 4,
                width * 4,
                bordered.data() + (row + kTextureBorder) * rowBytes + kTextureBorder * 4
            );
        }

        MTLTextureDescriptor *descriptor = [MTLTextureDescriptor
            texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                         width:static_cast<NSUInteger>(width + kTextureBorder * 2)
                                        height:static_cast<NSUInteger>(height + kTextureBorder * 2)
                                     mipmapped:YES];
        id<MTLTexture> texture = [renderer_.device newTextureWithDescriptor:descriptor];

        if (!texture) {
            return nil;
        }

        [texture replaceRegion:MTLRegionMake2D(0, 0, descriptor.width, descriptor.height)
                   mipmapLevel:0
                     withBytes:bordered.data()
                   bytesPerRow:static_cast<NSUInteger>(rowBytes)];

        if (!blit_) {
            commandBuffer_ = [renderer_.commandQueue commandBuffer];
            blit_ = [commandBuffer_ blitCommandEncoder];
        }

        [blit_ generateMipmapsForTexture:texture];
        return texture;
    }

private:
    ATRNumericTextRenderer *renderer_;
    ATRGlyphSnapshot *snapshot_;
    id<MTLCommandBuffer> commandBuffer_;
    id<MTLBlitCommandEncoder> blit_;
};

} // namespace

@interface ATRNumericTextTransition ()
- (void)renderTransactionFrame;
- (void)displayLinkDidFire;
@end

// Its first frame for new content goes out with the Core Animation
// transaction that hides the host's drawing: `displayLayer:` runs in the
// transaction's display phase, after layout has settled.
@interface ATRNumericTextOverlay : UIView
@property (nonatomic, weak, nullable) ATRNumericTextTransition *effect;
@end

@implementation ATRNumericTextOverlay

+ (Class)layerClass {
    return CAMetalLayer.class;
}

- (void)displayLayer:(CALayer *)layer {
    [self.effect renderTransactionFrame];
}

@end

// Breaks the retain cycle between a display link and its target.
@interface ATRNumericTextFrameTarget : NSObject
@property (nonatomic, weak, nullable) ATRNumericTextTransition *effect;
@end

@implementation ATRNumericTextFrameTarget

- (void)tick:(CADisplayLink *)link {
    [self.effect displayLinkDidFire];
}

@end

#endif

@implementation ATRNumericTextTransition {
#if !TARGET_OS_OSX
    Configuration _configuration;
    ATRNumericTextRenderer *_renderer;
    ATRNumericTextOverlay *_overlay;
    CADisplayLink *_displayLink;
    void (^_completion)(void);
    __weak UIView *_host;
    // Where glyphs come from is kept in this view's coordinates: the host's
    // frame changing must not move them, while scrolling must.
    __weak UIView *_anchor;
    // The host's origin in the anchor's coordinates as of the last frame,
    // which is where glyphs riding with the host were shown.
    CGPoint _hostOrigin;
    std::vector<Glyph> _glyphs;
    // End of the last line, in host coordinates.
    CGPoint _textEnd;
    id<MTLBuffer> _vertexBuffers[kVertexBufferCount];
    NSUInteger _vertexBufferIndex;
    CFTimeInterval _animationEnd;
    // The latest snapshot handed over, and whether new content came with it
    // or with one it replaced.
    ATRGlyphSnapshot *_pendingSnapshot;
    BOOL _pendingIsNewContent;
    BOOL _awaitsTransaction;
#endif
}

+ (ATRTextTransitionPrewarmResult)prewarm {
    return rendererStore().prewarm();
}

+ (void)keptCountsFrom:(const ATRGlyphAtom *)from
                 count:(NSUInteger)fromCount
                    to:(const ATRGlyphAtom *)to
                 count:(NSUInteger)toCount
                prefix:(NSUInteger *)prefix
                suffix:(NSUInteger *)suffix {
    size_t keptPrefix = 0;
    size_t keptSuffix = 0;
    keptCounts(from, from ? fromCount : 0, to, to ? toCount : 0, keptPrefix, keptSuffix);
    *prefix = keptPrefix;
    *suffix = keptSuffix;
}

#if TARGET_OS_OSX

- (BOOL)beginOnHost:(ATRPlatformView *)host snapshot:(ATRGlyphSnapshot *)snapshot completion:(void (^)(void))completion {
    return NO;
}

- (void)transitionToSnapshot:(ATRGlyphSnapshot *)snapshot {}

- (BOOL)relayoutWithSnapshot:(ATRGlyphSnapshot *)snapshot {
    return NO;
}

- (void)cancel {}

#else

- (void)dealloc {
    [_displayLink invalidate];
    [_overlay removeFromSuperview];
}

- (BOOL)beginOnHost:(UIView *)host snapshot:(ATRGlyphSnapshot *)snapshot completion:(void (^)(void))completion {
    ATRNumericTextRenderer *renderer = rendererStore().get();

    if (!renderer || !host.window) {
        return NO;
    }

    _renderer = renderer;
    _host = host;
    _completion = [completion copy];

    UIView *ancestor = host.superview;

    while (ancestor && ![ancestor isKindOfClass:UIScrollView.class]) {
        ancestor = ancestor.superview;
    }

    _anchor = ancestor ?: host.window;

    ATRNumericTextOverlay *overlay = [[ATRNumericTextOverlay alloc] initWithFrame:CGRectZero];
    overlay.effect = self;
    overlay.userInteractionEnabled = NO;
    overlay.opaque = NO;
    overlay.backgroundColor = UIColor.clearColor;
    overlay.contentScaleFactor = host.window.screen.scale;
    auto *layer = static_cast<CAMetalLayer *>(overlay.layer);
    layer.device = renderer.device;
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.opaque = NO;
    // Snapshots are drawn in sRGB; without a color space a wide-gamut screen
    // would show their values unmatched.
    auto colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    layer.colorspace = colorSpace;
    CGColorSpaceRelease(colorSpace);
    [host addSubview:overlay];
    _overlay = overlay;

    _hostOrigin = [host convertPoint:host.bounds.origin toView:_anchor];
    _glyphs.clear();
    TextureBatch textures(_renderer, snapshot);

    for (NSUInteger index = 0; index < snapshot.atomCount; ++index) {
        const ATRGlyphAtom &atom = snapshot.atoms[index];
        _glyphs.push_back({
            atom,
            textures.make(atom),
            Track::resting(atom.origin.x),
            Track::resting(atom.origin.y),
            {1, 1, 0, false, false},
            {0, 0, 0, false, false},
        });
    }

    if (snapshot.atomCount > 0) {
        const ATRGlyphAtom &last = snapshot.atoms[snapshot.atomCount - 1];
        _textEnd = CGPointMake(last.origin.x + last.advance, last.origin.y);
    }

    // The host hides its own drawing in this transaction, so the overlay
    // must show the current content in it too.
    [self scheduleFrame];
    return YES;
}

// The host calls these two during layout, and what it hands over may be
// laid out for bounds it is about to lose. So the snapshot is only kept, and
// the last one is taken up once layout has settled, in the transaction's
// display phase.
- (void)transitionToSnapshot:(ATRGlyphSnapshot *)snapshot {
    _pendingSnapshot = snapshot;
    _pendingIsNewContent = YES;
    [self scheduleFrame];
}

- (BOOL)relayoutWithSnapshot:(ATRGlyphSnapshot *)snapshot {
    _pendingIsNewContent = _pendingSnapshot ? _pendingIsNewContent : NO;
    _pendingSnapshot = snapshot;
    [self scheduleFrame];
    return YES;
}

- (void)cancel {
    [_displayLink invalidate];
    _displayLink = nil;
    [_overlay removeFromSuperview];
    _overlay = nil;
    _completion = nil;
    _pendingSnapshot = nil;
    _awaitsTransaction = NO;
    _glyphs.clear();
}

#pragma mark - Animation state

- (void)changeToSnapshot:(ATRGlyphSnapshot *)snapshot {
    CFTimeInterval now = CACurrentMediaTime();
    const Spring presenceSpring = _configuration.presence;
    const Spring shiftSpring = _configuration.shift;
    double settle = std::max(presenceSpring.settlingDuration(), shiftSpring.settlingDuration());

    std::erase_if(_glyphs, [&](const Glyph &glyph) {
        return glyph.removing && now > glyph.presence.start + settle;
    });

    // The host may already sit somewhere else for the new content. The old
    // content is taken in the anchor's coordinates from where it was last
    // drawn; the new content stays in host coordinates, since the host can
    // still be moved by layout this object never hears of.
    const CGPoint origin = _hostOrigin;
    const bool rides = _anchoring == ATRNumericTextAnchoringView;
    // With the view as the anchoring, where old content comes from is put
    // back into host coordinates, so that it rides along.
    auto fromX = [&](double value) { return rides ? value - origin.x : value; };
    auto fromY = [&](double value) { return rides ? value - origin.y : value; };
    auto rest = [&](const Glyph &glyph) {
        return CGPointMake(
            glyph.x.to + (glyph.x.toRides ? origin.x : 0),
            glyph.y.to + (glyph.y.toRides ? origin.y : 0)
        );
    };

    const ATRGlyphAtom *incoming = snapshot.atoms;
    const size_t incomingCount = snapshot.atomCount;
    const CGPoint previousEnd = CGPointMake(_textEnd.x + origin.x, _textEnd.y + origin.y);

    if (incomingCount > 0) {
        const ATRGlyphAtom &last = incoming[incomingCount - 1];
        _textEnd = CGPointMake(last.origin.x + last.advance, last.origin.y);
    }

    std::vector<size_t> live;
    std::vector<ATRGlyphAtom> liveAtoms;

    for (size_t index = 0; index < _glyphs.size(); ++index) {
        if (!_glyphs[index].removing) {
            live.push_back(index);
            liveAtoms.push_back(_glyphs[index].atom);
        }
    }

    size_t prefix = 0;
    size_t suffix = 0;
    keptCounts(liveAtoms.data(), liveAtoms.size(), incoming, incomingCount, prefix, suffix);

    // Changed glyphs have no partner; they follow the stretch of the gap
    // between the kept prefix and suffix. That only holds while the gap sits
    // on one line before and after, and both sides have content; otherwise
    // they fade in place.
    CGPoint oldStart = prefix < live.size() ? rest(_glyphs[live[prefix]]) : previousEnd;
    CGPoint oldEnd = suffix > 0 ? rest(_glyphs[live[live.size() - suffix]]) : previousEnd;
    CGPoint newStart = prefix < incomingCount ? incoming[prefix].origin : _textEnd;
    CGPoint newEnd = suffix > 0 ? incoming[incomingCount - suffix].origin : _textEnd;
    bool stretches = !live.empty() && incomingCount > 0
        && std::abs(oldStart.y - oldEnd.y) < 0.5 && std::abs(newStart.y - newEnd.y) < 0.5;
    double oldWidth = std::max<double>(oldEnd.x - oldStart.x, 0.001);
    double newWidth = std::max<double>(newEnd.x - newStart.x, 0.001);

    TextureBatch textures(_renderer, snapshot);

    for (size_t index = 0; index < prefix + suffix; ++index) {
        Glyph &glyph = _glyphs[index < prefix ? live[index] : live[live.size() - prefix - suffix + index]];
        const ATRGlyphAtom &target = incoming[index < prefix ? index : incomingCount - prefix - suffix + index];
        double x = valueOf(glyph.x, presenceSpring, now, origin.x);
        double y = valueOf(glyph.y, presenceSpring, now, origin.y);
        glyph.atom = target;
        glyph.texture = textures.make(target);
        glyph.x = {fromX(x), target.origin.x, now, rides, true};
        glyph.y = {fromY(y), target.origin.y, now, rides, true};
    }

    size_t removedCount = live.size() - prefix - suffix;
    size_t insertedCount = incomingCount - prefix - suffix;
    double span = std::clamp(
        _configuration.staggerStep * (static_cast<double>(std::max(removedCount, insertedCount)) - 1),
        0.0,
        _configuration.maxStagger
    );
    bool rightToLeft = _host.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    auto delay = [&](size_t index, size_t count) {
        if (count <= 1) {
            return 0.0;
        }

        return span * static_cast<double>(rightToLeft ? count - 1 - index : index) / static_cast<double>(count - 1);
    };
    double enterFrom = _direction == ATRNumericTextDirectionDownward ? -1 : 1;

    for (size_t index = 0; index < removedCount; ++index) {
        Glyph &glyph = _glyphs[live[prefix + index]];
        CFTimeInterval start = now + delay(index, removedCount);
        double x = valueOf(glyph.x, presenceSpring, now, origin.x);
        double y = valueOf(glyph.y, presenceSpring, now, origin.y);

        if (stretches) {
            double target = newStart.x + (rest(glyph).x - oldStart.x) * (newEnd.x - newStart.x) / oldWidth;
            glyph.x = {fromX(x), target, start, rides, true};
            glyph.y = {fromY(y), newStart.y, start, rides, true};
        } else {
            // Fades where it is, on screen or in the view.
            glyph.x = {fromX(x), fromX(x), start, rides, rides};
            glyph.y = {fromY(y), fromY(y), start, rides, rides};
        }

        glyph.presence = {valueOf(glyph.presence, presenceSpring, now), 0, start};
        glyph.shift = {valueOf(glyph.shift, shiftSpring, now), -enterFrom, start};
        glyph.removing = true;
    }

    std::vector<Glyph> result;
    result.reserve(_glyphs.size() + insertedCount);

    for (const Glyph &glyph : _glyphs) {
        if (glyph.removing) {
            result.push_back(glyph);
        }
    }

    for (size_t index = 0; index < prefix; ++index) {
        result.push_back(_glyphs[live[index]]);
    }

    for (size_t index = 0; index < insertedCount; ++index) {
        const ATRGlyphAtom &atom = incoming[prefix + index];
        CFTimeInterval start = now + delay(index, insertedCount);
        // Without the stretch it appears in its place, wherever the host is.
        Track x = {atom.origin.x, atom.origin.x, start, true, true};
        Track y = {atom.origin.y, atom.origin.y, start, true, true};

        if (stretches) {
            x = {fromX(oldStart.x + (atom.origin.x - newStart.x) * (oldEnd.x - oldStart.x) / newWidth), atom.origin.x, start, rides, true};
            y = {fromY(oldStart.y), atom.origin.y, start, rides, true};
        }

        result.push_back({atom, textures.make(atom), x, y, {0, 1, start}, {enterFrom, 0, start}});
    }

    for (size_t index = live.size() - suffix; index < live.size(); ++index) {
        result.push_back(_glyphs[live[index]]);
    }

    _glyphs = std::move(result);
    _animationEnd = now + span + settle;
}

// The same glyphs laid out again: they carry on toward their new places.
- (void)moveToSnapshot:(ATRGlyphSnapshot *)snapshot {
    CFTimeInterval now = CACurrentMediaTime();
    const Spring spring = _configuration.presence;
    const bool rides = _anchoring == ATRNumericTextAnchoringView;
    TextureBatch textures(_renderer, snapshot);
    size_t next = 0;

    for (Glyph &glyph : _glyphs) {
        if (glyph.removing || next >= snapshot.atomCount) {
            continue;
        }

        const ATRGlyphAtom &atom = snapshot.atoms[next++];
        glyph.atom = atom;
        glyph.texture = textures.make(atom);

        // A glyph resting in its place, or about to appear in it, simply has
        // a new place. One on its way carries on from where it was drawn.
        if (glyph.x.fromRides && glyph.y.fromRides && glyph.x.from == glyph.x.to && glyph.y.from == glyph.y.to) {
            glyph.x = {atom.origin.x, atom.origin.x, glyph.x.start, true, true};
            glyph.y = {atom.origin.y, atom.origin.y, glyph.y.start, true, true};
        } else if (std::abs(glyph.x.to - atom.origin.x) > 0.01 || std::abs(glyph.y.to - atom.origin.y) > 0.01) {
            CFTimeInterval start = std::max(now, glyph.x.start);
            double x = valueOf(glyph.x, spring, now, _hostOrigin.x) - (rides ? _hostOrigin.x : 0);
            double y = valueOf(glyph.y, spring, now, _hostOrigin.y) - (rides ? _hostOrigin.y : 0);
            glyph.x = {x, atom.origin.x, start, rides, true};
            glyph.y = {y, atom.origin.y, std::max(now, glyph.y.start), rides, true};
            _animationEnd = std::max(_animationEnd, start + spring.settlingDuration());
        }
    }

    if (snapshot.atomCount > 0) {
        const ATRGlyphAtom &last = snapshot.atoms[snapshot.atomCount - 1];
        _textEnd = CGPointMake(last.origin.x + last.advance, last.origin.y);
    }
}

- (BOOL)hasSameGlyphsAsSnapshot:(ATRGlyphSnapshot *)snapshot {
    size_t next = 0;

    for (const Glyph &glyph : _glyphs) {
        if (glyph.removing) {
            continue;
        }

        if (next >= snapshot.atomCount || snapshot.atoms[next].font != glyph.atom.font
            || snapshot.atoms[next].glyph != glyph.atom.glyph) {
            return NO;
        }

        ++next;
    }

    return next == snapshot.atomCount;
}

#pragma mark - Frames

// The next frame goes out with the transaction that changes the host, so no
// frame shows neither the host's drawing nor the overlay's.
- (void)scheduleFrame {
    UIView *host = _host;

    if (!host || !_overlay) {
        return;
    }

    // A layer without area is not asked to display.
    if (CGRectIsEmpty(_overlay.frame)) {
        [UIView performWithoutAnimation:^{
            self->_overlay.frame = host.bounds;
        }];
    }

    _awaitsTransaction = YES;
    _displayLink.paused = YES;
    static_cast<CAMetalLayer *>(_overlay.layer).presentsWithTransaction = YES;
    [_overlay.layer setNeedsDisplay];
}

- (void)renderTransactionFrame {
    if (!_awaitsTransaction) {
        return;
    }

    if (ATRGlyphSnapshot *pending = _pendingSnapshot) {
        _pendingSnapshot = nil;

        // Laid out again with other glyphs, as when a narrower width
        // truncates, is a change of content like any other.
        if (_pendingIsNewContent || ![self hasSameGlyphsAsSnapshot:pending]) {
            [self changeToSnapshot:pending];
        } else {
            [self moveToSnapshot:pending];
        }
    }

    [self fitOverlay];
    [self renderFrame];
}

- (void)displayLinkDidFire {
    [self renderFrame];

    if (CACurrentMediaTime() >= _animationEnd) {
        _displayLink.paused = YES;

        if (_completion) {
            _completion();
        }
    }
}

- (void)fitOverlay {
    UIView *host = _host;

    if (!host || !_overlay) {
        return;
    }

    // Wide enough for glyphs on their way in from outside the host, plus the
    // room they fly and blur into.
    CGRect extent = host.bounds;
    CGFloat margin = 0;
    CGPoint origin = [host convertPoint:host.bounds.origin toView:_anchor];

    for (const Glyph &glyph : _glyphs) {
        CGSize size = glyph.atom.tile.size;
        margin = std::max(margin, size.height * 1.5);
        CGPoint ends[] = {
            CGPointMake(glyph.x.from - (glyph.x.fromRides ? 0 : origin.x), glyph.y.from - (glyph.y.fromRides ? 0 : origin.y)),
            CGPointMake(glyph.x.to - (glyph.x.toRides ? 0 : origin.x), glyph.y.to - (glyph.y.toRides ? 0 : origin.y)),
        };

        for (CGPoint end : ends) {
            extent = CGRectUnion(extent, CGRectMake(end.x, end.y - size.height, size.width, size.height));
        }
    }

    CGFloat scale = host.window.screen.scale ?: 1;
    CGRect frame = CGRectInset(extent, -margin, -margin);
    CGRect aligned = CGRectMake(
        std::floor(CGRectGetMinX(frame) * scale) / scale,
        std::floor(CGRectGetMinY(frame) * scale) / scale,
        std::ceil(CGRectGetWidth(frame) * scale) / scale,
        std::ceil(CGRectGetHeight(frame) * scale) / scale
    );
    [UIView performWithoutAnimation:^{
        self->_overlay.frame = aligned;
    }];
    _overlay.contentScaleFactor = scale;
    static_cast<CAMetalLayer *>(_overlay.layer).drawableSize = CGSizeMake(
        CGRectGetWidth(aligned) * scale,
        CGRectGetHeight(aligned) * scale
    );
}

// Where the host is right now is read every frame rather than remembered:
// layout can move it without laying it out again, for example when something
// above it in a list changes height. Presentation layers are used so that a
// frame change the caller animates does not drag the glyphs along. The frame
// that goes out with a transaction is the exception: presentation layers
// still show the state before it, which is only right for layers about to
// animate.
- (void)updateHostOrigin {
    UIView *host = _host;
    UIView *anchor = _anchor;

    if (!host || !anchor) {
        return;
    }

    BOOL usesModel = _awaitsTransaction;

    for (CALayer *layer = host.layer; layer && layer != anchor.layer; layer = layer.superlayer) {
        usesModel = usesModel && layer.animationKeys.count == 0;
    }

    CALayer *hostLayer = usesModel ? host.layer : (host.layer.presentationLayer ?: host.layer);
    CALayer *anchorLayer = usesModel ? anchor.layer : (anchor.layer.presentationLayer ?: anchor.layer);
    _hostOrigin = [hostLayer convertPoint:hostLayer.bounds.origin toLayer:anchorLayer];
}

- (void)renderFrame {
    auto *layer = static_cast<CAMetalLayer *>(_overlay.layer);
    BOOL transactional = _awaitsTransaction;
    [self updateHostOrigin];

    id<CAMetalDrawable> drawable = layer ? [layer nextDrawable] : nil;
    id<MTLCommandBuffer> commandBuffer = drawable ? [_renderer.commandQueue commandBuffer] : nil;

    if (!commandBuffer) {
        [self finishTransactionFrame:transactional];
        return;
    }

    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = drawable.texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];

    CFTimeInterval now = CACurrentMediaTime();
    CGSize size = _overlay.bounds.size;
    double contentScale = _overlay.contentScaleFactor;
    CGPoint origin = CGPointMake(_hostOrigin.x + _overlay.frame.origin.x, _hostOrigin.y + _overlay.frame.origin.y);
    const Configuration &configuration = _configuration;

    std::vector<float> vertices;
    std::vector<id<MTLTexture>> textures;
    vertices.reserve(_glyphs.size() * 4 * kFloatsPerVertex);

    for (const Glyph &glyph : _glyphs) {
        id<MTLTexture> texture = glyph.texture;

        if (!texture || size.width <= 0 || size.height <= 0) {
            continue;
        }

        textures.push_back(texture);
        const ATRGlyphAtom &atom = glyph.atom;
        double presence = valueOf(glyph.presence, configuration.presence, now);
        double shift = valueOf(glyph.shift, configuration.shift, now);
        double x = valueOf(glyph.x, configuration.presence, now, _hostOrigin.x) - origin.x;
        double baseline = valueOf(glyph.y, configuration.presence, now, _hostOrigin.y) - origin.y;
        double scale = configuration.scale + (1 - configuration.scale) * presence;
        double sigma = std::max(0.0, 1 - presence) * configuration.relativeBlur * atom.inkHeight / 2;
        double border = kTextureBorder / contentScale;
        double centerX = atom.advance / 2;
        double centerY = atom.midline;
        double width = texture.width / contentScale * scale;
        double height = texture.height / contentScale * scale;
        double left = x + centerX + (CGRectGetMinX(atom.tile) - atom.origin.x - border - centerX) * scale;
        double top = baseline + shift * configuration.relativeOffset * atom.inkHeight + centerY
            + (CGRectGetMinY(atom.tile) - atom.origin.y - border - centerY) * scale;
        double pad = sigma * 3;

        for (int corner = 0; corner < 4; ++corner) {
            double u = corner % 2 == 0 ? -pad / width : 1 + pad / width;
            double v = corner < 2 ? -pad / height : 1 + pad / height;
            vertices.push_back(static_cast<float>((left + u * width) / size.width * 2 - 1));
            vertices.push_back(static_cast<float>(1 - (top + v * height) / size.height * 2));
            vertices.push_back(static_cast<float>(u));
            vertices.push_back(static_cast<float>(v));
            vertices.push_back(static_cast<float>(std::clamp(presence, 0.0, 1.0)));
            vertices.push_back(static_cast<float>(sigma * contentScale / scale));
        }
    }

    if (!vertices.empty()) {
        NSUInteger length = vertices.size() * sizeof(float);
        // Several frames can be in flight; each writes its own buffer.
        _vertexBufferIndex = (_vertexBufferIndex + 1) % kVertexBufferCount;
        id<MTLBuffer> buffer = _vertexBuffers[_vertexBufferIndex];

        if (!buffer || buffer.length < length) {
            buffer = [_renderer.device newBufferWithLength:length * 2 options:MTLResourceStorageModeShared];
            _vertexBuffers[_vertexBufferIndex] = buffer;
        }

        std::memcpy(buffer.contents, vertices.data(), length);
        [encoder setRenderPipelineState:_renderer.pipeline];
        [encoder setVertexBuffer:buffer offset:0 atIndex:0];
        [encoder setFragmentSamplerState:_renderer.sampler atIndex:0];

        for (NSUInteger index = 0; index < textures.size(); ++index) {
            [encoder setFragmentTexture:textures[index] atIndex:0];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:index * 4 vertexCount:4];
        }
    }

    [encoder endEncoding];

    if (transactional) {
        [commandBuffer commit];
        [commandBuffer waitUntilScheduled];
        [drawable present];
    } else {
        [commandBuffer presentDrawable:drawable];
        [commandBuffer commit];
    }

    [self finishTransactionFrame:transactional];
}

- (void)finishTransactionFrame:(BOOL)transactional {
    if (!transactional) {
        return;
    }

    _awaitsTransaction = NO;
    static_cast<CAMetalLayer *>(_overlay.layer).presentsWithTransaction = NO;

    if (!_displayLink) {
        ATRNumericTextFrameTarget *target = [[ATRNumericTextFrameTarget alloc] init];
        target.effect = self;
        _displayLink = [CADisplayLink displayLinkWithTarget:target selector:@selector(tick:)];
        [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }

    _displayLink.paused = NO;
}

#endif

@end
