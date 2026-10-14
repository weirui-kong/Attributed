// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import <XCTest/XCTest.h>

#import "ATRDocumentBuilder.h"
#import "ATRGlyphSnapshot.h"

#include <cmath>
#include <vector>

namespace {

ATRTextStyle fontStyle(int32_t font) {
    ATRTextStyle style = {};
    style.fields = ATRTextStyleFieldFont;
    style.font = font;
    return style;
}

bool onPixelGrid(CGFloat value, CGFloat scale) {
    return std::abs(value * scale - std::round(value * scale)) < 1e-6;
}

std::vector<ATRGlyphAtom> atomsOf(ATRGlyphSnapshot *snapshot) {
    return std::vector<ATRGlyphAtom>(snapshot.atoms, snapshot.atoms + snapshot.atomCount);
}

} // namespace

@interface GlyphSnapshotTests : XCTestCase
@end

@implementation GlyphSnapshotTests

- (ATRGlyphSnapshot *)snapshotOf:(NSArray<NSString *> *)paragraphs width:(double)width scale:(CGFloat)scale {
    ATRDocumentBuilder *builder = [[ATRDocumentBuilder alloc] init];
    int32_t font = [builder registerFont:[ATRPlatformFont systemFontOfSize:24]];

    for (NSString *text in paragraphs) {
        [builder beginParagraph:{} textStyle:fontStyle(font)];
        [builder appendText:text];
        [builder endParagraph];
    }

    ATRTextLayout *layout = [[builder finish] layoutWithContainer:{width, INFINITY, 0, ATRLineHeightModeTypographic}
                                                  truncationToken:nil];
    ATRRenderSnapshot *render = [[ATRRenderSnapshot alloc] initWithLayout:layout
                                                               appearance:nil
                                                                   images:@{}
                                              gradientsIncludeColorGlyphs:NO];
    return [[ATRGlyphSnapshot alloc] initWithRenderSnapshot:render
                                                     bounds:CGRectMake(0, 0, width, layout.size.height)
                                                      scale:scale];
}

- (void)testEveryGlyphIsAnAtomInVisualOrder {
    auto atoms = atomsOf([self snapshotOf:@[@"$12.50"] width:300 scale:2]);

    XCTAssertEqual(atoms.size(), 6u);

    for (size_t index = 1; index < atoms.size(); ++index) {
        XCTAssertGreaterThan(atoms[index].origin.x, atoms[index - 1].origin.x);
        XCTAssertEqual(atoms[index].origin.y, atoms[0].origin.y);
    }
}

- (void)testDigitsAndSeparatorsNextToThemAreNumeric {
    auto atoms = atomsOf([self snapshotOf:@[@"$1,2.5 a.b"] width:400 scale:2]);
    std::vector<bool> numeric;

    for (const ATRGlyphAtom &atom : atoms) {
        numeric.push_back(atom.numeric);
    }

    XCTAssertEqual(numeric, (std::vector<bool>{false, true, true, true, true, true, false, false, false, false}));
}

- (void)testEqualGlyphsHaveEqualKeysAcrossDocuments {
    auto first = atomsOf([self snapshotOf:@[@"105"] width:300 scale:2]);
    auto second = atomsOf([self snapshotOf:@[@"150"] width:300 scale:2]);

    XCTAssertEqual(first[0].font, second[0].font);
    XCTAssertEqual(first[0].glyph, second[0].glyph);
    XCTAssertEqual(first[1].glyph, second[2].glyph);
    XCTAssertEqual(first[2].glyph, second[1].glyph);
    XCTAssertNotEqual(first[1].glyph, first[2].glyph);
}

- (void)testTilesAreDisjointOnThePixelGridAndInsideTheBitmap {
    CGFloat scale = 3;
    ATRGlyphSnapshot *snapshot = [self snapshotOf:@[@"Total: 1,024.75 items", @"Wrapped onto lines"] width:120 scale:scale];
    auto atoms = atomsOf(snapshot);

    XCTAssertGreaterThan(atoms.size(), 20u);

    for (size_t index = 0; index < atoms.size(); ++index) {
        CGRect tile = atoms[index].tile;

        for (CGFloat value : {CGRectGetMinX(tile), CGRectGetMinY(tile), CGRectGetMaxX(tile), CGRectGetMaxY(tile)}) {
            XCTAssertTrue(onPixelGrid(value, scale), @"atom %zu", index);
        }

        if (CGRectIsEmpty(tile)) {
            continue;
        }

        XCTAssertTrue(CGRectContainsRect(snapshot.frame, tile), @"atom %zu", index);

        for (size_t other = index + 1; other < atoms.size(); ++other) {
            CGRect overlap = CGRectIntersection(tile, atoms[other].tile);
            XCTAssertTrue(CGRectIsEmpty(overlap) || CGRectGetWidth(overlap) * CGRectGetHeight(overlap) < 1e-9,
                          @"atoms %zu and %zu", index, other);
        }
    }
}

- (void)testTilesCoverTheGlyphInk {
    ATRGlyphSnapshot *snapshot = [self snapshotOf:@[@"8"] width:100 scale:2];
    ATRGlyphAtom atom = snapshot.atoms[0];
    const auto *pixels = static_cast<const uint8_t *>(snapshot.pixels);
    size_t inside = 0;
    size_t outside = 0;

    for (size_t y = 0; y < snapshot.pixelHeight; ++y) {
        for (size_t x = 0; x < snapshot.pixelWidth; ++x) {
            if (pixels[y * snapshot.bytesPerRow + x * 4 + 3] == 0) {
                continue;
            }

            CGPoint point = CGPointMake(CGRectGetMinX(snapshot.frame) + (x + 0.5) / 2, CGRectGetMinY(snapshot.frame) + (y + 0.5) / 2);
            (CGRectContainsPoint(atom.tile, point) ? inside : outside) += 1;
        }
    }

    XCTAssertGreaterThan(inside, 0u);
    XCTAssertEqual(outside, 0u);
    XCTAssertGreaterThan(atom.inkHeight, 0);
    XCTAssertLessThan(atom.midline, 0);
}

- (void)testNoRenderSnapshotGivesAnEmptyOne {
    ATRGlyphSnapshot *snapshot = [[ATRGlyphSnapshot alloc] initWithRenderSnapshot:nil
                                                                           bounds:CGRectMake(0, 0, 50, 20)
                                                                            scale:2];

    XCTAssertEqual(snapshot.atomCount, 0u);
    XCTAssertTrue(snapshot.atoms == nullptr);
    XCTAssertTrue(CGRectEqualToRect(snapshot.frame, CGRectMake(0, 0, 50, 20)));
    XCTAssertEqual(snapshot.pixelWidth, 100u);
}

@end
