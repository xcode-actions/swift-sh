import Foundation
#if canImport(System)
import System
#else
import SystemPackage
#endif

import ArgumentParser
import Logging
import ProcessInvocation



struct Run : AsyncParsableCommand {
	
	@OptionGroup
	var globalOptions: GlobalOptions
	
	@OptionGroup
	var runOptions: BuildAndRunOptions
	
	@Flag(name: .customLong("set-fg-pgid-for-stdin"), inversion: .prefixedNo, help: """
		Set this to set the foreground group ID associated with the controlling terminal to “your” stdin.
		What this means is you’ll receive text typed in the Terminal when reading stdin if the flag is set, otherwise you won’t.
		This is disabled by default because this will _also_ send you the signals, and Swift ignores the Ctrl-C signal for some reasons, which is not convenient.
		""")
	var setFgPgID = false
	
	@Argument(parsing: .captureForPassthrough)
	var scriptArguments: [String] = []
	
	func run() async throws {
		let (args, swiftFile, stdinData, _, cleanup) = try await runOptions.prepareRun(logger: logger)
		defer {cleanup()}
		
		let allArgs = args + [swiftFile] + scriptArguments
		logger.trace("Running script.", metadata: ["invocation": .array((["swift"] + allArgs).map{ "\($0)" })])
		let (exitCode, terminationReason) = try await ProcessInvocation(
			swiftPath, args: allArgs, usePATH: true,
			stdinRedirect: stdinData.flatMap{ .send($0) } ?? .none(setFgPgID: setFgPgID), stdoutRedirect: .none, stderrRedirect: .none,
			signalHandling: { .mapForChild(for: $0, with: [.interrupt: .terminated]/* Swift eats the interrupts for some reasons… */) },
			expectedTerminations: .some(nil)
		).invokeAndStreamOutput(checkValidTerminations: false/* Doesn’t matter, all terminations are valid. */, outputHandler: { _, _, _ in })
		
		if terminationReason == .uncaughtSignal {
			logger.info("Script received uncaught signal.")
		}
		throw ExitCode(exitCode)
	}
	
}


fileprivate extension Run {
	
	var logger: Logger {
		globalOptions.logger
	}
	
	var swiftPath: FilePath {
		runOptions.swiftPath
	}
	
}
