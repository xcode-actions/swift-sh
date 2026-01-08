import Foundation

import ArgumentParser
import Logging



@main
struct SwiftSH : AsyncParsableCommand {
	
	static let configuration: CommandConfiguration = .init(
		commandName: "swift sh",
		version: "dev", /* DO NOT REMOVE: VERSION_PLACEHOLDER. This tag is used to automatically replace the version when building in Homebrew. */
		subcommands: [
			Build.self,
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
