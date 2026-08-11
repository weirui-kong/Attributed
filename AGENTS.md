# Code Comments

- Never use Swift documentation comments (`///`). Use only regular line comments (`//`).
- Add comments only where behavior, intent, constraints, or a non-obvious decision needs explanation.
- Do not comment self-explanatory code.
- Do not restate or explain function signatures unless that explanation is necessary to understand non-obvious behavior.
- Every Swift source file starts with the following MIT license header. This legal notice is an exception to the comment-minimization rules:

  ```swift
  // Copyright 2026 Kong Weirui
  // SPDX-License-Identifier: MIT
  ```

- `Package.swift` is the only exception: its required `// swift-tools-version:` declaration stays on the first line, directly before the license header.
