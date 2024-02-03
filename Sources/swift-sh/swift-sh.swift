import Foundation

import ArgumentParser
import Logging



@main
struct SwiftSH : AsyncParsableCommand {
	
	static let configuration: CommandConfiguration = .init(
		commandName: "swift sh",
		version: "3.0.0", /* TODO: Find a way to automatically update this when creating new versions… */
		subcommands: [
			Eject.self,
			Run.self
		],
		defaultSubcommand: Run.self
	)
	
	@OptionGroup
	var globalOptions: GlobalOptions
	
}


extension SwiftSH {
	
	fileprivate var logger: Logger {
		globalOptions.logger
	}
	
}
