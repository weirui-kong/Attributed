// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Foundation

public extension Attributed {
struct InteractionID: Hashable {
    let rawValue: UUID

    init() {
        rawValue = UUID()
    }
}

enum Interaction {
    case url(URL)
    case action(() -> Void)
}
}

extension Attributed {
final class InteractionRegistry {
    private var storage: [InteractionID: Interaction] = [:]

    func register(_ interaction: Interaction) -> InteractionID {
        let id = InteractionID()
        storage[id] = interaction
        return id
    }

    func interaction(for id: InteractionID) -> Interaction? {
        storage[id]
    }
}
}

public extension NSAttributedString.Key {
    static let attributedInteractionID = NSAttributedString.Key(
        "Attributed.InteractionID"
    )
}
