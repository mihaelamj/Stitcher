// Stitcher - Multi-file OpenAPI $ref resolution

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Yams

/// Stitches multi-file OpenAPI specs into a single document.
/// Resolves external $refs from local files and network URLs.
public actor Stitcher {
    private var cache: [String: Any] = [:]
    private var resolving: Set<String> = []

    public init() {}

    /// Stitch a spec from a file path
    public func stitch(from path: String) async throws -> String {
        let url = URL(fileURLWithPath: path)
        return try await stitch(from: url)
    }

    /// Stitch a spec from a URL (file or network)
    public func stitch(from url: URL) async throws -> String {
        let content = try await fetchContent(from: url)
        let resolved = try await resolveDocument(content: content, baseURL: url)
        return try serializeToYAML(resolved)
    }

    /// Stitch a spec from raw YAML/JSON content
    public func stitch(content: String, baseURL: URL? = nil) async throws -> String {
        let base = baseURL ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let resolved = try await resolveDocument(content: content, baseURL: base)
        return try serializeToYAML(resolved)
    }

    /// Clear the resolution cache
    public func clearCache() {
        cache.removeAll()
        resolving.removeAll()
    }

    // MARK: - Document Resolution

    private func resolveDocument(content: String, baseURL: URL) async throws -> Any {
        guard let parsed = try Yams.load(yaml: content) else {
            throw StitcherError.parseError("Failed to parse YAML")
        }
        return try await resolveValue(parsed, baseURL: baseURL)
    }

    private func resolveValue(_ value: Any, baseURL: URL) async throws -> Any {
        if let dict = value as? [String: Any] {
            return try await resolveDictionary(dict, baseURL: baseURL)
        } else if let array = value as? [Any] {
            return try await resolveArray(array, baseURL: baseURL)
        } else {
            return value
        }
    }

    private func resolveDictionary(_ dict: [String: Any], baseURL: URL) async throws -> Any {
        if let ref = dict["$ref"] as? String {
            // Internal ref (same document) - keep as is
            if ref.hasPrefix("#") {
                return dict
            }
            // External ref - resolve it
            return try await resolveExternalRef(ref, baseURL: baseURL, originalDict: dict)
        }

        // Not a $ref - recursively resolve all values
        var result: [String: Any] = [:]
        for (key, value) in dict {
            result[key] = try await resolveValue(value, baseURL: baseURL)
        }
        return result
    }

    private func resolveArray(_ array: [Any], baseURL: URL) async throws -> [Any] {
        var result: [Any] = []
        for item in array {
            result.append(try await resolveValue(item, baseURL: baseURL))
        }
        return result
    }

    private func resolveExternalRef(_ ref: String, baseURL: URL, originalDict: [String: Any]) async throws -> Any {
        let parts = ref.components(separatedBy: "#")
        let filePath = parts[0]
        let jsonPointer = parts.count > 1 ? "#" + parts[1] : nil

        let resolvedURL = resolveURL(filePath, relativeTo: baseURL)
        let cacheKey = resolvedURL.absoluteString

        // Check for circular references
        if resolving.contains(cacheKey) {
            throw StitcherError.circularReference(ref)
        }

        // Check cache
        if let cached = cache[cacheKey] {
            return try extractWithPointer(from: cached, pointer: jsonPointer, originalDict: originalDict)
        }

        // Mark as resolving
        resolving.insert(cacheKey)
        defer { resolving.remove(cacheKey) }

        // Fetch and parse the referenced file
        let content = try await fetchContent(from: resolvedURL)
        guard let parsed = try Yams.load(yaml: content) else {
            throw StitcherError.parseError("Failed to parse: \(resolvedURL)")
        }

        // Recursively resolve refs in the fetched content
        let resolved = try await resolveValue(parsed, baseURL: resolvedURL)

        // Cache the resolved content
        cache[cacheKey] = resolved

        return try extractWithPointer(from: resolved, pointer: jsonPointer, originalDict: originalDict)
    }

    private func extractWithPointer(from value: Any, pointer: String?, originalDict: [String: Any]) throws -> Any {
        var result: Any = value

        if let pointer = pointer, pointer != "#" {
            result = try navigateJSONPointer(value, pointer: pointer)
        }

        // If the result is an array or scalar, return as-is
        guard var dict = result as? [String: Any] else {
            return result
        }

        // Merge any additional properties from the original dict (except $ref)
        for (key, value) in originalDict where key != "$ref" {
            if dict[key] == nil {
                dict[key] = value
            }
        }

        return dict
    }

    private func navigateJSONPointer(_ value: Any, pointer: String) throws -> Any {
        var path = pointer
        if path.hasPrefix("#") {
            path = String(path.dropFirst())
        }
        if path.hasPrefix("/") {
            path = String(path.dropFirst())
        }

        if path.isEmpty {
            return value
        }

        // Split and decode JSON pointer escapes
        let components = path.components(separatedBy: "/").map { component in
            component
                .replacingOccurrences(of: "~1", with: "/")
                .replacingOccurrences(of: "~0", with: "~")
        }

        var current: Any = value
        for component in components {
            if let dict = current as? [String: Any] {
                guard let next = dict[component] else {
                    throw StitcherError.refNotFound(pointer)
                }
                current = next
            } else if let array = current as? [Any], let index = Int(component) {
                guard index >= 0 && index < array.count else {
                    throw StitcherError.refNotFound(pointer)
                }
                current = array[index]
            } else {
                throw StitcherError.refNotFound(pointer)
            }
        }

        return current
    }

    // MARK: - Fetching

    private func fetchContent(from url: URL) async throws -> String {
        if url.isFileURL {
            return try String(contentsOf: url, encoding: .utf8)
        } else {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw StitcherError.fetchFailed(url)
            }

            guard let text = String(data: data, encoding: .utf8) else {
                throw StitcherError.invalidEncoding(url)
            }

            return text
        }
    }

    private func resolveURL(_ ref: String, relativeTo base: URL) -> URL {
        if ref.hasPrefix("http://") || ref.hasPrefix("https://") {
            return URL(string: ref)!
        }

        let baseDir = base.deletingLastPathComponent()
        return baseDir.appendingPathComponent(ref).standardized
    }

    // MARK: - Serialization

    private func serializeToYAML(_ value: Any) throws -> String {
        let node = try convertToNode(value)
        return try Yams.serialize(node: node)
    }

    private func convertToNode(_ value: Any) throws -> Node {
        switch value {
        case let string as String:
            return Node.scalar(.init(string))
        case let int as Int:
            return Node.scalar(.init(String(int)))
        case let double as Double:
            return Node.scalar(.init(String(double)))
        case let bool as Bool:
            return Node.scalar(.init(bool ? "true" : "false"))
        case let array as [Any]:
            let nodes = try array.map { try convertToNode($0) }
            return Node.sequence(.init(nodes))
        case let dict as [String: Any]:
            var pairs: [(Node, Node)] = []
            for key in dict.keys.sorted() {
                let keyNode = Node.scalar(.init(key))
                let valueNode = try convertToNode(dict[key]!)
                pairs.append((keyNode, valueNode))
            }
            return Node.mapping(.init(pairs))
        case is NSNull:
            return Node.scalar(.init("null"))
        default:
            return Node.scalar(.init(String(describing: value)))
        }
    }
}

// MARK: - Errors

public enum StitcherError: Error, LocalizedError {
    case fetchFailed(URL)
    case invalidEncoding(URL)
    case parseError(String)
    case circularReference(String)
    case refNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .fetchFailed(let url):
            return "Failed to fetch: \(url)"
        case .invalidEncoding(let url):
            return "Invalid encoding: \(url)"
        case .parseError(let message):
            return "Parse error: \(message)"
        case .circularReference(let path):
            return "Circular reference: \(path)"
        case .refNotFound(let ref):
            return "Reference not found: \(ref)"
        }
    }
}
