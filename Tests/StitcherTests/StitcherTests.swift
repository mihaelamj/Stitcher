import XCTest
@testable import Stitcher

final class StitcherTests: XCTestCase {

    // MARK: - Basic Tests

    func testStitcherInit() async {
        let stitcher = Stitcher()
        XCTAssertNotNil(stitcher)
    }

    func testStitchSimpleContent() async throws {
        let stitcher = Stitcher()
        let content = """
        openapi: 3.0.3
        info:
          title: Test API
          version: 1.0.0
        paths: {}
        """

        let result = try await stitcher.stitch(content: content)
        XCTAssertTrue(result.contains("openapi: 3.0.3"))
    }

    func testContentWithoutRefsPassesThrough() async throws {
        let stitcher = Stitcher()
        let content = """
        openapi: 3.0.3
        info:
          title: Test
          version: 1.0.0
        components:
          schemas:
            User:
              type: object
              properties:
                name:
                  type: string
        paths: {}
        """

        let result = try await stitcher.stitch(content: content)
        XCTAssertTrue(result.contains("User"))
        XCTAssertTrue(result.contains("type: object"))
    }

    func testContentWithInternalRefs() async throws {
        let stitcher = Stitcher()
        let content = """
        openapi: 3.0.3
        info:
          title: Test
          version: 1.0.0
        components:
          schemas:
            User:
              type: object
            UserList:
              type: array
              items:
                $ref: '#/components/schemas/User'
        paths: {}
        """

        // Internal refs starting with # should be left alone
        let result = try await stitcher.stitch(content: content)
        XCTAssertTrue(result.contains("#/components/schemas/User"))
    }

    // MARK: - Multi-file Tests

    func testStitchMultiFileSpec() async throws {
        let stitcher = Stitcher()
        let fixturesURL = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
        let specPath = fixturesURL.appendingPathComponent("acme/zephyr-data/spec.yml").path

        guard FileManager.default.fileExists(atPath: specPath) else {
            throw XCTSkip("Fixtures not available at \(specPath)")
        }

        let result = try await stitcher.stitch(from: specPath)

        // Should contain the main spec content
        XCTAssertTrue(result.contains("openapi: 3.0.3"), "Should contain OpenAPI version")
        XCTAssertTrue(result.contains("zephyr-data"), "Should contain spec title")

        // Should have resolved external refs
        XCTAssertFalse(result.contains("$ref: ./"), "Should not have relative refs")
        XCTAssertFalse(result.contains("$ref: ../"), "Should not have parent refs")
    }

    func testStitchFromFileURL() async throws {
        let stitcher = Stitcher()
        let fixturesURL = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
        let specURL = fixturesURL.appendingPathComponent("acme/zephyr-data/spec.yml")

        guard FileManager.default.fileExists(atPath: specURL.path) else {
            throw XCTSkip("Fixtures not available")
        }

        let result = try await stitcher.stitch(from: specURL)
        XCTAssertTrue(result.contains("openapi:"), "Should contain OpenAPI marker")
    }

    func testStitchResolvesNestedRefs() async throws {
        let stitcher = Stitcher()
        let fixturesURL = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
        let specPath = fixturesURL.appendingPathComponent("acme/zephyr-data/spec.yml").path

        guard FileManager.default.fileExists(atPath: specPath) else {
            throw XCTSkip("Fixtures not available")
        }

        let result = try await stitcher.stitch(from: specPath)

        // Should have resolved refs from ../core/ folder
        XCTAssertTrue(result.contains("apiError") || result.contains("ApiError") || result.contains("flurbinator"),
                      "Should contain resolved core schemas")
    }

    // MARK: - Petstore Multifile

    func testStitchPetstoreMultifile() async throws {
        let stitcher = Stitcher()
        let fixturesURL = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
        let specPath = fixturesURL.appendingPathComponent("petstore-multifile/src/openapi.yaml").path

        guard FileManager.default.fileExists(atPath: specPath) else {
            throw XCTSkip("Fixtures not available")
        }

        let result = try await stitcher.stitch(from: specPath)

        XCTAssertTrue(result.contains("Swagger Petstore"))
        XCTAssertFalse(result.contains("$ref: \"./"), "Should not have relative refs")
        XCTAssertFalse(result.contains("$ref: '../"), "Should not have parent refs")
    }

    // MARK: - OpenAPI Boilerplate

    func testStitchOpenapiBoilerplate() async throws {
        let stitcher = Stitcher()
        let fixturesURL = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
        let specPath = fixturesURL.appendingPathComponent("openapi-boilerplate/src/openapi.yaml").path

        guard FileManager.default.fileExists(atPath: specPath) else {
            throw XCTSkip("Fixtures not available")
        }

        let result = try await stitcher.stitch(from: specPath)

        XCTAssertTrue(result.contains("Swagger Petstore"))
        XCTAssertFalse(result.contains("$ref: \"./"), "Should not have relative refs")
    }

    // MARK: - Swagger Multifile Example (Complex)

    func testStitchSwaggerMultifileExample() async throws {
        let stitcher = Stitcher()
        let fixturesURL = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
        let specPath = fixturesURL.appendingPathComponent("swagger-multifile-example/swagger.yaml").path

        guard FileManager.default.fileExists(atPath: specPath) else {
            throw XCTSkip("Fixtures not available")
        }

        let result = try await stitcher.stitch(from: specPath)

        // This spec uses JSON pointer escaping (~1 for /)
        XCTAssertTrue(result.contains("Multi-file swagger"))
        XCTAssertFalse(result.contains("$ref: './"), "Should not have relative refs")
        XCTAssertFalse(result.contains("$ref: '../"), "Should not have parent refs")
    }

    // MARK: - Remote URL Tests

    func testStitchFromRemoteURL() async throws {
        let stitcher = Stitcher()
        // Single-file spec from Swagger Petstore
        let url = URL(string: "https://petstore3.swagger.io/api/v3/openapi.yaml")!

        let result = try await stitcher.stitch(from: url)

        XCTAssertTrue(result.contains("openapi:"))
        XCTAssertTrue(result.contains("Petstore"))
    }

    // MARK: - Already Stitched (No External Refs)

    func testAlreadyStitchedSpecPassesThrough() async throws {
        let stitcher = Stitcher()
        // Stripe API is a large single-file spec with no external refs
        let url = URL(string: "https://raw.githubusercontent.com/stripe/openapi/master/openapi/spec3.yaml")!

        let result = try await stitcher.stitch(from: url)

        // Should pass through without modification (only internal #refs)
        XCTAssertTrue(result.contains("openapi:"))
        XCTAssertTrue(result.contains("Stripe"))
    }

    // MARK: - Error Cases

    func testCircularReferenceThrows() async throws {
        let stitcher = Stitcher()

        // Create temp files with circular refs
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileA = """
        openapi: 3.0.3
        info:
          title: Circular A
          version: 1.0.0
        components:
          schemas:
            A:
              $ref: ./b.yaml
        paths: {}
        """

        let fileB = """
        $ref: ./a.yaml#/components/schemas/A
        """

        try fileA.write(to: tempDir.appendingPathComponent("a.yaml"), atomically: true, encoding: .utf8)
        try fileB.write(to: tempDir.appendingPathComponent("b.yaml"), atomically: true, encoding: .utf8)

        do {
            _ = try await stitcher.stitch(from: tempDir.appendingPathComponent("a.yaml"))
            XCTFail("Should have thrown circular reference error")
        } catch let error as StitcherError {
            if case .circularReference = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    func testInvalidYAMLThrows() async throws {
        let stitcher = Stitcher()
        let invalid = """
        openapi: 3.0.3
        info:
          title: Bad YAML
          version: 1.0.0
        paths:
          - this is invalid
            yaml: [[[
        """

        do {
            _ = try await stitcher.stitch(content: invalid)
            XCTFail("Should have thrown parse error")
        } catch {
            // Expected
        }
    }

    func testMissingFileThrows() async throws {
        let stitcher = Stitcher()
        let content = """
        openapi: 3.0.3
        info:
          title: Missing Ref
          version: 1.0.0
        components:
          schemas:
            Missing:
              $ref: ./does-not-exist.yaml
        paths: {}
        """

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let specFile = tempDir.appendingPathComponent("spec.yaml")
        try content.write(to: specFile, atomically: true, encoding: .utf8)

        do {
            _ = try await stitcher.stitch(from: specFile)
            XCTFail("Should have thrown error for missing file")
        } catch {
            // Expected
        }
    }
}
