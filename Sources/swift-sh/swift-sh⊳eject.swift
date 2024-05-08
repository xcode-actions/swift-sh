import Foundation

import ArgumentParser
import Logging



struct Eject : AsyncParsableCommand {
	
	@OptionGroup
	var globalOptions: GlobalOptions
	
	@Flag(name: .shortAndLong)
	var force: Bool = false
	
	@OptionGroup
	var scriptOptions: ScriptOptions
	
	func run() async throws {
		logger.error("Not implemented")
		throw ExitCode(1)
	}
	
}


extension Eject {
	
	fileprivate var logger: Logger {
		globalOptions.logger
	}
	
}
