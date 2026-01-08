import Foundation
import Testing

@testable import SwiftSH_Helpers


struct HelpersTests {
	
	init() {
		isBeingTested = true
	}
	
	@Test
	func testChangeDirectoryToRepoRoot() throws {
		try changeCurrentDirectoryPath(.scriptRepoRoot)
	}
	
}
