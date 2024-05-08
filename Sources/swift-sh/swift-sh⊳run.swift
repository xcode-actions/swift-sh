import Foundation
#if canImport(System)
import System
#else
import SystemPackage
#endif

import ArgumentParser
import Crypto
import Logging
import ProcessInvocation
import XDG



struct Run : AsyncParsableCommand {
	
	@OptionGroup
	var globalOptions: GlobalOptions
	
	@Flag(name: .long)
	var useSSHForGithubDependencies: Bool = false
	
	@Flag(name: .customShort("c"))
	var scriptPathIsContent = false
	
	@Flag(name: .long, inversion: .prefixedNo)
	var skipPackageOnNoRemoteModules = true
	
	@Flag(name: .long, inversion: .prefixedNo)
	var disableSandboxForPackageResolution = false
	
	@Option(name: .long)
	var swiftPath: FilePath = "swift"
	
	@Argument
	var scriptPathOrContent: String
	
	@Argument(parsing: .captureForPassthrough)
	var scriptArguments: [String] = []
	
	func run() async throws {
		let fm = FileManager.default
		let xdgDirs = try BaseDirectories(prefixAll: "swift-sh")
		
		let scriptSource = try (
			!scriptPathIsContent ?
			ScriptSource(path: FilePath(scriptPathOrContent), fileManager: fm) :
			ScriptSource(content: scriptPathOrContent, fileManager: fm, logger: logger)
		)
		defer {
			if let scriptPath = scriptSource.scriptPath, scriptPath.isTmp {
				/* Notes:
				 * We should probably also register a sigaction to remove the temporary file in case of a terminating signal.
				 * Or we could remove the file just after launching swift with it (to be tested). */
				let p = scriptPath.0.string
				do    {try fm.removeItem(atPath: p)}
				catch {logger.warning("Failed removings temporary file.", metadata: ["file-path": "\(p)", "error": "\(error)"])}
			}
		}
		logger.debug("Running script", metadata: ["script-name": "\(scriptSource.scriptName)", "script-path": scriptSource.scriptPath.flatMap{ ["value": "\($0.0)", "temporary": "\($0.isTmp)"] }, "script-arguments": .array(scriptArguments.map{ "\($0)" })].compactMapValues{ $0 })
		
		let scriptPathForSwift: String
		var scriptData: (Data, hash: Data)?
		if let scriptPath = scriptSource.scriptPath {
			scriptData = nil
			scriptPathForSwift = scriptPath.0.string
		} else {
			scriptData = (Data(), hash: Data())
			scriptPathForSwift = "-"
		}
		
		let depsPackage = try DepsPackage(
			scriptSource: scriptSource, scriptData: &scriptData,
			useSSHForGithubDependencies: useSSHForGithubDependencies,
			skipPackageOnNoRemoteModules: skipPackageOnNoRemoteModules,
			fileManager: fm, logger: logger
		)
		let swiftArgs = try await {
			guard let depsPackage else {
				return [String]()
			}
			/* Retrieve the REPL invocation in package folder path.
			 * Note: This is not protected in regard to multiple scripts trying to use the same store entry.
			 * TODO: Make the REPL invocation retrieval concurrent-safe, or at least concurrent-protected. */
			let packageFolderRelativePath = FilePath("store").appending(depsPackage.packageHash.reduce("", { $0 + String(format: "%02x", $1) }))
			let packageFolderPath = try xdgDirs.ensureCacheDirPath(packageFolderRelativePath)
			let ret = try await depsPackage.retrieveREPLInvocation(
				packageFolder: packageFolderPath,
				disableSandboxForPackageResolution: disableSandboxForPackageResolution,
				fileManager: fm, logger: logger
			)
			/* If retrieving the REPL invocation was successful, we mark the store entry as being used.
			 * This is only for clients and has no use for swift-sh itself (allows light cleaning of the cache folder).
			 * Note: We are not concurrent-safe for this either. */
			let packageFolderAliasDiscriminator = Insecure.MD5
				.hash(data: scriptData?.hash ?? Data(scriptPathForSwift.utf8))
				.reduce("", { $0 + String(format: "%02x", $1) })
			let markersFolderPath = try xdgDirs.ensureCacheDirPath(FilePath("markers"))
			let packageFolderAliasPath = markersFolderPath.appending("\(scriptSource.scriptName)--\(packageFolderAliasDiscriminator)")
			do {
				try? fm.removeItem(at: packageFolderAliasPath.url)
				/* Do not use the URL variant of this method as it is not possible (AFAICT) to create a relative link with it. */
				try fm.createSymbolicLink(atPath: packageFolderAliasPath.string, withDestinationPath: FilePath("..").appending(packageFolderRelativePath.components).string)
			} catch {
				logger.warning("Failed to create marker link in swift-sh cache.", metadata: ["error": "\(error)", "marker-path": "\(packageFolderAliasPath.string)"])
			}
			return ret
		}()
		
		let allArgs = swiftArgs + [scriptPathForSwift] + scriptArguments
		logger.trace("Running script.", metadata: ["invocation": .array((["swift"] + allArgs).map{ "\($0)" })])
		let (exitCode, terminationReason) = try await ProcessInvocation(
			swiftPath, args: allArgs, usePATH: true,
			stdinRedirect: scriptData.flatMap{ .send($0.0) } ?? .none(), stdoutRedirect: .none, stderrRedirect: .none,
			signalHandling: { .mapForChild(for: $0, with: [.interrupt: .terminated]/* Swift eats the interrupts for some reasons… */) },
			expectedTerminations: .some(nil)
		).invokeAndStreamOutput(checkValidTerminations: false/* Doesn’t matter, all terminations are valid. */, outputHandler: { _, _, _ in })
		
		if terminationReason == .uncaughtSignal {
			logger.info("Script received uncaught signal.")
		}
		throw ExitCode(exitCode)
	}
	
}


extension Run {
	
	fileprivate var logger: Logger {
		globalOptions.logger
	}
	
}
