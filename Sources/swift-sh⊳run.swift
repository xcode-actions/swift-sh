import Foundation

import ArgumentParser
import Logging
import StreamReader



struct Run : AsyncParsableCommand {
	
	@OptionGroup
	var globalOptions: GlobalOptions
	
	@Argument
	var scriptPath: String
	
	@Argument(parsing: .captureForPassthrough)
	var scriptArguments: [String] = []
	
	func run() async throws {
		logger.debug("Running script", metadata: ["script-path": "\(scriptPath)", "script-arguments": .array(scriptArguments.map{ "\($0)" })])
		let scriptURL = URL(fileURLWithPath: scriptPath)
		
		let fh = try FileHandle(forReadingFrom: scriptURL)
		defer {try? fh.close()}
		
		/* Let’s parse the source file.
		 * We’re doing a very bad job at parsing, but that’s mostly on purpose. */
		let streamReader = FileHandleReader(stream: fh, bufferSize: 3 * 1024, bufferSizeIncrement: 1024)
		while let (lineData, newLineData) = try streamReader.readLine() {
//			logger.trace("Received new source line data.", metadata: ["line-data": "\(lineData.reduce("", { $0 + String(format: "%02x", $1) }))"])
			guard let lineStr = String(data: lineData, encoding: .utf8) else {
				/* We ignore non-UTF8 lines.
				 * There should be none (valid UTF8 is a requirement for Swift files), 
				 *  but if we find any it’s not our job to reject them. */
				continue
			}
			logger.trace("Parsing new source line.", metadata: ["line": "\(lineStr)"])
			guard let importSpec = ImportSpecification(line: lineStr) else {
				if (try? #/^(\s*@testable)?\s*import(\s+(class|enum|struct))?\s+[\w_]+(\.[^\s]+)?\s+(//|/*)/#.firstMatch(in: lineStr)) != nil {
					logger.notice("Found a line starting with import followed by a comment that failed to match an import spec.", metadata: ["line": "\(lineStr)"])
				}
				continue
			}
			logger.debug("Found new import specification.", metadata: ["import-spec": "\(importSpec)", "line": "\(lineStr)"])
		}
	}
	
}


extension Run {
	
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
