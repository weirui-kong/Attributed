// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import UIKit

// Images are generated in code so the demo needs no bundled assets.
enum DemoImages {
    static func symbol(_ name: String, color: UIColor, pointSize: CGFloat = 20) -> UIImage {
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        let symbol = UIImage(systemName: name, withConfiguration: configuration)?
            .withTintColor(color, renderingMode: .alwaysOriginal) ?? UIImage()
        return UIGraphicsImageRenderer(size: symbol.size).image { _ in
            symbol.draw(at: .zero)
        }
    }

    static func swatch(_ color: UIColor, size: CGSize = CGSize(width: 18, height: 18)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in
            color.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 4).fill()
        }
    }

    static func landscape(size: CGSize = CGSize(width: 600, height: 300)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor.systemIndigo.cgColor, UIColor.systemTeal.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: nil)!
            context.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )

            UIColor.white.withAlphaComponent(0.85).setFill()
            let sun = CGRect(x: size.width * 0.68, y: size.height * 0.18, width: size.height * 0.28, height: size.height * 0.28)
            UIBezierPath(ovalIn: sun).fill()

            UIColor.black.withAlphaComponent(0.25).setFill()
            let hills = UIBezierPath()
            hills.move(to: CGPoint(x: 0, y: size.height))
            hills.addQuadCurve(
                to: CGPoint(x: size.width * 0.55, y: size.height * 0.62),
                controlPoint: CGPoint(x: size.width * 0.25, y: size.height * 0.45)
            )
            hills.addQuadCurve(
                to: CGPoint(x: size.width, y: size.height * 0.7),
                controlPoint: CGPoint(x: size.width * 0.8, y: size.height * 0.8)
            )
            hills.addLine(to: CGPoint(x: size.width, y: size.height))
            hills.close()
            hills.fill()
        }
    }
}
