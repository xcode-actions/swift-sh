import Foundation

import ArgumentParser
import Logging



@main
struct SwiftSH : AsyncParsableCommand {
	
	static let configuration: CommandConfiguration = .init(
		commandName: "swift sh",
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
