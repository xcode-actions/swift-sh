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

/*
import LegibleError
import Foundation
import Command
import Script
import Path


do {
	let isTTY = isatty(fileno(stdin)) == 1
	let mode = try Mode(for: CommandLine.arguments, isTTY: isTTY)
	
	switch mode {
		case .run(let input, let args):
			try Command.run(input, arguments: args)
		case .eject(let path, let force):
			try Command.eject(path, force: force)
		case .edit(let path):
			try Command.edit(path: path)
		case .editor(let path):
			try Command.editor(path: path)
		case .clean(let path):
			try Command.clean(path)
		case .help:
			print(CommandLine.usage)
	}
} catch CommandLine.Error.invalidUsage {
	fputs("""
		error: invalid usage
		\(CommandLine.usage)\n
		""", stderr)
	exit(3)
} catch {
	fputs("error: \(error.legibleLocalizedDescription)\n", stderr)
	exit(2)
}*/
