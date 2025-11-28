# 🪡 Stitcher

Swift library that resolves external `$ref` references in multi-file/multi-folder OpenAPI specs and stitches them into a single document.

[![CI](https://github.com/mihaelamj/Stitcher/actions/workflows/ci.yml/badge.svg)](https://github.com/mihaelamj/Stitcher/actions/workflows/ci.yml)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmihaelamj%2FStitcher%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/mihaelamj/Stitcher)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmihaelamj%2FStitcher%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/mihaelamj/Stitcher)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

## Features

- Resolves external `$ref` references from local files and URLs
- Handles nested references across multiple folders (`../core/schemas/`)
- Supports JSON pointer syntax (`#/components/schemas/User`)
- Detects circular references
- Caches resolved files for performance
- Works on macOS, iOS, and Linux

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mihaelamj/Stitcher.git", from: "1.0.0")
]
```

Then add `Stitcher` to your target dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: ["Stitcher"]
)
```

## Usage

```swift
import Stitcher

let stitcher = Stitcher()

// From file path
let result = try await stitcher.stitch(from: "/path/to/openapi.yaml")

// From URL (local or remote)
let url = URL(string: "https://example.com/api/openapi.yaml")!
let result = try await stitcher.stitch(from: url)

// From string content
let yaml = """
openapi: 3.0.3
info:
  title: My API
  version: 1.0.0
components:
  schemas:
    User:
      $ref: ./schemas/user.yaml
paths: {}
"""
let result = try await stitcher.stitch(content: yaml, baseURL: baseURL)
```

## Example

Given this multi-file structure:

```
api/
├── openapi.yaml
├── schemas/
│   ├── user.yaml
│   └── error.yaml
└── paths/
    └── users.yaml
```

Where `openapi.yaml` contains:

```yaml
openapi: 3.0.3
info:
  title: My API
  version: 1.0.0
components:
  schemas:
    User:
      $ref: ./schemas/user.yaml
    Error:
      $ref: ./schemas/error.yaml
paths:
  /users:
    $ref: ./paths/users.yaml
```

Stitcher will resolve all `$ref` references and produce a single YAML document with all schemas and paths inlined.

## Error Handling

```swift
do {
    let result = try await stitcher.stitch(from: path)
} catch StitcherError.circularReference(let ref) {
    print("Circular reference detected: \(ref)")
} catch StitcherError.fetchFailed(let url) {
    print("Failed to fetch: \(url)")
} catch StitcherError.parseError(let message) {
    print("Parse error: \(message)")
} catch StitcherError.refNotFound(let ref) {
    print("Reference not found: \(ref)")
}
```

## License

MIT
