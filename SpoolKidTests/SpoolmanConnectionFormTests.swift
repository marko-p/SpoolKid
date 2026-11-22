import Testing
@testable import SpoolKid

struct SpoolmanConnectionFormTests {
    @Test func connectionFormTypeExists() async throws {
        // Smoke test: the extracted shared form type exists.
        // Full UI verification is manual (see plan). The real gate is the
        // build + existing suite + manual welcome-wizard flow.
        let typeName = String(describing: SpoolmanConnectionForm.self)
        #expect(typeName == "SpoolmanConnectionForm")
    }
}
