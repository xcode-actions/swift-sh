import Foundation

import ArgumentParser
import Logging
import SystemPackage



/* Command that creates a new script with the given name.
 * Basically it’s a “copy template” command… */
struct New : AsyncParsableCommand {
	
	@OptionGroup
	var globalOptions: GlobalOptions
	
	@Argument
	var scriptName: FilePath.Component
	
	func run() async throws {
		logger.error("Not implemented")
		throw ExitCode(1)
	}
	
}


extension New {
	
	fileprivate var logger: Logger {
		globalOptions.logger
	}
	
}
