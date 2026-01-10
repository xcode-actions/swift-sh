import Foundation

import ArgumentParser
import Logging
import SystemPackage



struct Edit : AsyncParsableCommand {
	
	@OptionGroup
	var globalOptions: GlobalOptions
	
	@Argument
	var scriptPath: FilePath
	
	func run() async throws {
		logger.error("Not implemented")
		throw ExitCode(1)
	}
	
}


extension Edit {
	
	fileprivate var logger: Logger {
		globalOptions.logger
	}
	
}
