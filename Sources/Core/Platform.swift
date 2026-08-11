// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#if canImport(UIKit)
import UIKit

public typealias PlatformColor = UIColor
public typealias PlatformFont = UIFont
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit

public typealias PlatformColor = NSColor
public typealias PlatformFont = NSFont
public typealias PlatformImage = NSImage
#else
#error("Core requires UIKit or AppKit.")
#endif
