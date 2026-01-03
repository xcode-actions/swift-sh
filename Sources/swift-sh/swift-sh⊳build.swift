import Foundation

import ArgumentParser
import Logging
import ProcessInvocation
import SystemPackage
import UnwrapOrThrow



struct Build : AsyncParsableCommand {
	
	@OptionGroup
	var globalOptions: GlobalOptions
	
	@OptionGroup
	var runOptions: BuildAndRunOptions
	
	func run() async throws {
		let finalCompiledFilePath = (
			scriptPathIsContent || scriptPath == "-" ?
				"main" :
				scriptPath.removingLastComponent().appending(try scriptPath.stem ?! InternalError(message: "cannot get stem of input path"))
		)
		if !scriptPathIsContent {
			guard finalCompiledFilePath != scriptPath else {
				throw ValidationError("Cannot compile a file that does not have an extension.")
			}
		}
		
		let (args, swiftFile, stdinData, packageFolderPath, cleanup) = try await runOptions.prepareRun(forceCopySource: true, logger: logger)
		defer {cleanup()}
		
		let swiftFilePath = FilePath(swiftFile)
		let compiledFilePath = try swiftFilePath.removingLastComponent().appending(swiftFilePath.stem ?! InternalError(message: "no stem"))
		
		guard swiftFilePath.extension == "swift" else {
			throw InternalError(message: "unexpected swift file path extension")
		}
		
		try await ProcessInvocation(
			/* The “headerpad_max_install_names” option allows later addition of the rpath required for the binary to run. */
			FilePath(swiftPath.string + "c"), args: args + ["-Xlinker", "-headerpad_max_install_names"] + [swiftFile], usePATH: true,
			workingDirectory: swiftFilePath.removingLastComponent().url,
			stdinRedirect: stdinData.flatMap{ .send($0) } ?? .none(), stdoutRedirect: .none, stderrRedirect: .none,
			signalHandling: { .mapForChild(for: $0, with: [.interrupt: .terminated]/* Swift eats the interrupts for some reasons… */) }
		).invokeAndStreamOutput(outputHandler: { _, _, _ in })
		if let packageFolderPath {
			try await ProcessInvocation(
				"install_name_tool", "-add_rpath", packageFolderPath.appending([".build", "release"]).string, compiledFilePath.string
			).invokeAndStreamOutput(outputHandler: { _, _, _ in })
		}
		_ = try? FileManager.default.removeItem(at: finalCompiledFilePath.url)
		try FileManager.default.moveItem(at: compiledFilePath.url, to: finalCompiledFilePath.url)
	}
	
	private struct InternalError : Error {var message: String}
	
}


fileprivate extension Build {
	
	var logger: Logger {
		globalOptions.logger
	}
	
	var scriptPathIsContent: Bool {
		runOptions.scriptOptions.scriptPathIsContent
	}
	
	var scriptPath: FilePath {
		/* We allow ourselves this conversion as we know we won’t call this accessor if the path is content. */
		FilePath(runOptions.scriptOptions.scriptPathOrContent)
	}
	
	var swiftPath: FilePath {
		runOptions.swiftPath
	}
	
}
