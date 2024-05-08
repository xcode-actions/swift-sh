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
	
	@Argument(parsing: .captureForPassthrough)
	var scriptArguments: [String] = []
	
	func run() async throws {
		let (args, stdinData, cleanup) = try await runOptions.prepareRun(logger: logger)
		defer {cleanup()}
		
		let allArgs = args + scriptArguments
		logger.trace("Running script.", metadata: ["invocation": .array((["swift"] + allArgs).map{ "\($0)" })])
		let (exitCode, terminationReason) = try await ProcessInvocation(
			swiftPath, args: allArgs, usePATH: true,
			stdinRedirect: stdinData.flatMap{ .send($0) } ?? .none(), stdoutRedirect: .none, stderrRedirect: .none,
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
