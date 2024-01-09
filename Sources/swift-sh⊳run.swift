import Foundation
#if canImport(System)
import System
#else
import SystemPackage
#endif

import ArgumentParser
import Logging
import XDG



struct Run : AsyncParsableCommand {
	
	@OptionGroup
	var globalOptions: GlobalOptions
	
	@Flag(name: .long, inversion: .prefixedNo)
	var skipPackageOnNoRemoteModules = true
	
	@Argument
	var scriptPath: FilePath
	
	@Argument(parsing: .captureForPassthrough)
	var scriptArguments: [String] = []
	
	func run() async throws {
		let fm = FileManager.default
		let xdgDirs = try BaseDirectories(prefixAll: "swift-sh")
		
		/* Note: Our stdin detection probably lacks a lot of edge cases but we deem it enough. */
		/* TODO: The case of named pipes… */
		let isStdin = (scriptPath == "-" || scriptPath == "/dev/stdin")
		logger.debug("Running script", metadata: ["script-path": "\(!isStdin ? scriptPath : "<stdin>")", "script-arguments": .array(scriptArguments.map{ "\($0)" })])
		
		let depsPackage = try DepsPackage(scriptPath: scriptPath, isStdin: isStdin, xdgDirs: xdgDirs, fileManager: fm, logger: logger)
		print(try await depsPackage.retrieveREPLInvocation(skipPackageOnNoRemoteModules: skipPackageOnNoRemoteModules, fileManager: fm, logger: logger).joined(separator: " "))
	}
	
}


extension Run {
	
	fileprivate var logger: Logger {
		globalOptions.logger
	}
	
}
