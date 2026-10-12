// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#include "atr/render/Render.hpp"

#include <algorithm>
#include <unordered_map>

namespace atr {

namespace {

// Underline pattern lengths, alternating on and off, in multiples of the
// underline thickness.
const std::vector<double> &patternUnits(UnderlinePattern pattern) {
    static const std::vector<double> solid;
    static const std::vector<double> dot = {1, 1};
    static const std::vector<double> dash = {3, 2};
    static const std::vector<double> dashDot = {3, 2, 1, 2};
    static const std::vector<double> dashDotDot = {3, 2, 1, 2, 1, 2};

    switch (pattern) {
    case UnderlinePattern::Solid:
        return solid;
    case UnderlinePattern::Dot:
        return dot;
    case UnderlinePattern::Dash:
        return dash;
    case UnderlinePattern::DashDot:
        return dashDot;
    case UnderlinePattern::DashDotDot:
        return dashDotDot;
    }

    return solid;
}

CGRect makeCGRect(const Rect &rect) {
    return CGRectMake(rect.x, rect.y, rect.width, rect.height);
}

bool overlapsVertically(double top, double bottom, const Rect &clip) {
    return bottom >= clip.y && top <= clip.y + clip.height;
}

class Renderer {
public:
    Renderer(
        CGContextRef context,
        const Layout &layout,
        const Document &document,
        const ResolvedDocument &resolved,
        const RenderResources &resources,
        const Rect &clip
    )
        : context_(context),
          layout_(layout),
          document_(document),
          resolved_(resolved),
          resources_(resources),
          clip_(clip),
          colorSpace_(CFRef<CGColorSpaceRef>::adopt(CGColorSpaceCreateWithName(kCGColorSpaceSRGB))) {}

    void run() {
        CGContextSaveGState(context_);
        CGContextClipToRect(context_, makeCGRect(clip_));
        // Layout coordinates grow downward; flip glyphs back upright.
        CGContextSetTextMatrix(context_, CGAffineTransformMakeScale(1, -1));

        // Backgrounds first, so no line's background covers a neighboring
        // line's overflowing glyphs.
        forEachVisibleLine([this](const Line &line) { drawBackgrounds(line); });
        drawAttachments();
        forEachVisibleLine([this](const Line &line) { drawGlyphs(line); });
        drawDecorations();

        CGContextRestoreGState(context_);
    }

private:
    CGContextRef context_;
    const Layout &layout_;
    const Document &document_;
    const ResolvedDocument &resolved_;
    const RenderResources &resources_;
    const Rect clip_;
    CFRef<CGColorSpaceRef> colorSpace_;
    std::unordered_map<int32_t, CFRef<CGGradientRef>> gradients_;

    template <typename Body> void forEachVisibleLine(Body body) {
        for (const Line &line : layout_.lines) {
            if (overlapsVertically(line.drawnTop(), line.drawnBottom(), clip_)) {
                body(line);
            }
        }
    }

    CGColorRef color(int32_t index) const {
        if (index < 0 || static_cast<size_t>(index) >= resources_.colors.size()) {
            return nullptr;
        }

        return resources_.colors[index].get();
    }

    CGGradientRef gradient(int32_t index) {
        if (auto found = gradients_.find(index); found != gradients_.end()) {
            return found->second.get();
        }

        const Gradient &definition = document_.gradients()[index];
        auto colors = CFRef<CFMutableArrayRef>::adopt(
            CFArrayCreateMutable(nullptr, 0, &kCFTypeArrayCallBacks)
        );

        for (int32_t colorIndex : definition.colors) {
            if (CGColorRef value = color(colorIndex)) {
                CFArrayAppendValue(colors.get(), value);
            }
        }

        std::vector<CGFloat> locations;

        if (definition.locations && definition.locations->size() == definition.colors.size()) {
            locations.assign(definition.locations->begin(), definition.locations->end());
        }

        auto result = CFRef<CGGradientRef>::adopt(CGGradientCreateWithColors(
            colorSpace_.get(),
            colors.get(),
            locations.empty() ? nullptr : locations.data()
        ));
        CGGradientRef pointer = result.get();
        gradients_.emplace(index, std::move(result));
        return pointer;
    }

    // Draws over the current clip, laid out in the joined group rect so the
    // gradient stays continuous across runs, lines, and tiles.
    void drawGradient(int32_t index, std::optional<uint32_t> group, const Rect &fallback) {
        CGGradientRef value = gradient(index);

        if (!value) {
            return;
        }

        const Rect &rect = group ? layout_.gradientGroups[*group].rect : fallback;
        const Gradient &definition = document_.gradients()[index];
        CGPoint start = CGPointMake(
            rect.x + definition.startX * rect.width,
            rect.y + definition.startY * rect.height
        );
        CGPoint end = CGPointMake(
            rect.x + definition.endX * rect.width,
            rect.y + definition.endY * rect.height
        );
        CGContextDrawLinearGradient(
            context_,
            value,
            start,
            end,
            kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation
        );
    }

    void drawBackgrounds(const Line &line) {
        for (const LineRun &run : line.runs) {
            const ResolvedTextStyle &style = resolved_.styles[run.style];

            if (!style.backgroundColor) {
                continue;
            }

            if (CGColorRef value = color(*style.backgroundColor)) {
                CGContextSetFillColorWithColor(context_, value);
                CGContextFillRect(
                    context_,
                    CGRectMake(run.x, line.baseline - line.ascent, run.width, line.ascent + line.descent)
                );
            }
        }
    }

    void drawAttachments() {
        for (const AttachmentFrame &attachment : layout_.attachments) {
            const Rect &frame = attachment.frame;

            if (frame.width <= 0 || frame.height <= 0
                || !overlapsVertically(frame.y, frame.y + frame.height, clip_)
                || attachment.attachment >= resources_.images.size()) {
                continue;
            }

            CGImageRef image = resources_.images[attachment.attachment].get();

            if (!image) {
                continue;
            }

            // CGContextDrawImage assumes y grows upward.
            CGContextSaveGState(context_);
            CGContextTranslateCTM(context_, frame.x, frame.y + frame.height);
            CGContextScaleCTM(context_, 1, -1);
            CGContextDrawImage(context_, CGRectMake(0, 0, frame.width, frame.height), image);
            CGContextRestoreGState(context_);
        }
    }

    void drawGlyphs(const Line &line) {
        for (const LineRun &run : line.runs) {
            if (run.attachment) {
                continue;
            }

            const ResolvedTextStyle &style = resolved_.styles[run.style];
            double originX = line.x;
            double originY = line.baseline - style.baselineOffset;
            bool gradientFill = style.foreground.kind == FillKind::Gradient;

            if (!gradientFill || (run.colorGlyphs && !resources_.gradientsIncludeColorGlyphs)) {
                if (!gradientFill) {
                    if (CGColorRef value = color(style.foreground.index)) {
                        CGContextSetFillColorWithColor(context_, value);
                    }
                }

                CGContextSetTextPosition(context_, originX, originY);
                CTRunDraw(run.run.get(), context_, CFRangeMake(0, 0));
                continue;
            }

            Rect bounds = {run.x, line.drawnTop(), run.width, line.drawnBottom() - line.drawnTop()};
            CGContextSaveGState(context_);

            if (run.colorGlyphs) {
                // Color glyphs have no outlines to clip with; tint them by
                // compositing the gradient onto their own pixels.
                CGContextBeginTransparencyLayerWithRect(context_, makeCGRect(bounds), nullptr);
                CGContextSetTextPosition(context_, originX, originY);
                CTRunDraw(run.run.get(), context_, CFRangeMake(0, 0));
                CGContextSetBlendMode(context_, kCGBlendModeSourceIn);
                drawGradient(style.foreground.index, run.fillGroup, bounds);
                CGContextEndTransparencyLayer(context_);
            } else {
                CGContextSetTextDrawingMode(context_, kCGTextClip);
                CGContextSetTextPosition(context_, originX, originY);
                CTRunDraw(run.run.get(), context_, CFRangeMake(0, 0));
                drawGradient(style.foreground.index, run.fillGroup, bounds);
            }

            CGContextRestoreGState(context_);
        }
    }

    double cornerRadius(const Underline &underline, double thickness) const {
        switch (underline.corners) {
        case UnderlineCorners::Square:
            return 0;
        case UnderlineCorners::Radius:
            return std::min(underline.cornerRadius, thickness / 2);
        case UnderlineCorners::Capsule:
            return thickness / 2;
        }

        return 0;
    }

    void addPiece(CGMutablePathRef path, double minX, double maxX, double centerY, double thickness, double radius) {
        double width = maxX - minX;

        if (width <= 0) {
            return;
        }

        CGRect rect = CGRectMake(minX, centerY - thickness / 2, width, thickness);
        // CGPathAddRoundedRect requires radii within half of each side.
        double clamped = std::min({radius, width / 2, thickness / 2});

        if (clamped > 0) {
            CGPathAddRoundedRect(path, nullptr, rect, clamped, clamped);
        } else {
            CGPathAddRect(path, nullptr, rect);
        }
    }

    void drawDecorations() {
        for (const DecorationSegment &segment : layout_.decorations) {
            double thickness = segment.thickness;
            bool isDouble = segment.underline.lines == UnderlineLines::Double;
            double extent = isDouble ? thickness * 1.5 : thickness / 2;

            if (!overlapsVertically(segment.centerY - extent, segment.centerY + extent, clip_)) {
                continue;
            }

            std::vector<double> centers = isDouble
                ? std::vector<double>{segment.centerY - thickness, segment.centerY + thickness}
                : std::vector<double>{segment.centerY};
            double radius = cornerRadius(segment.underline, thickness);
            const std::vector<double> &units = patternUnits(segment.underline.pattern);
            auto path = CFRef<CGMutablePathRef>::adopt(CGPathCreateMutable());

            for (double centerY : centers) {
                if (units.empty()) {
                    addPiece(path.get(), segment.minX, segment.maxX, centerY, thickness, radius);
                    continue;
                }

                double x = segment.minX;
                size_t unit = 0;

                while (x < segment.maxX) {
                    double length = units[unit % units.size()] * thickness;

                    if (unit % 2 == 0) {
                        addPiece(path.get(), x, std::min(x + length, segment.maxX), centerY, thickness, radius);
                    }

                    x += length;
                    ++unit;
                }
            }

            if (segment.fill.kind == FillKind::Color) {
                if (CGColorRef value = color(segment.fill.index)) {
                    CGContextSetFillColorWithColor(context_, value);
                    CGContextAddPath(context_, path.get());
                    CGContextFillPath(context_);
                }

                continue;
            }

            Rect bounds = {
                segment.minX,
                segment.centerY - extent,
                segment.maxX - segment.minX,
                extent * 2,
            };
            CGContextSaveGState(context_);
            CGContextAddPath(context_, path.get());
            CGContextClip(context_);
            drawGradient(segment.fill.index, segment.group, bounds);
            CGContextRestoreGState(context_);
        }
    }
};

} // namespace

void render(
    CGContextRef context,
    const Layout &layout,
    const Document &document,
    const ResolvedDocument &resolved,
    const RenderResources &resources,
    const Rect &clip
) {
    Renderer(context, layout, document, resolved, resources, clip).run();
}

} // namespace atr
