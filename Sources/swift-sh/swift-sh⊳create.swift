import Foundation

import ArgumentParser
import Logging
import SystemPackage



/** Creates a new swift-sh script with some defaults (uses `ArgumentParser`, imports `SwiftSH_Helpers`, etc.). */
struct Create : AsyncParsableCommand {
	
	@OptionGroup
	var globalOptions: GlobalOptions
	
	@Flag(name: .shortAndLong)
	var force: Bool = false
	
	@Argument
	var scriptPath: FilePath
	
	func run() async throws {
		throw InternalError(message: "Not implemented")
	}
	
}
