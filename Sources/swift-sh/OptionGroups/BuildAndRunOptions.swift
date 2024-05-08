import Foundation
#if canImport(System)
import System
#else
import SystemPackage
#endif

import ArgumentParser
import Crypto
import Logging
import XDG



final class BuildAndRunOptions : ParsableArguments {
	
	@Flag(name: .long, inversion: .prefixedNo)
	var skipPackageOnNoRemoteModules = true
	
	@Flag(name: .long, inversion: .prefixedNo)
	var disableSandboxForPackageResolution = false
	
	@Option(name: .long)
	var swiftPath: FilePath = "swift"
	
	@OptionGroup
	var scriptOptions: ScriptOptions
	
	/* Returns the arguments that should be given to swift to run the script. */
	func prepareRun(forceCopySource: Bool = false, logger: Logger) async throws -> (swiftArgs: [String], swiftStdin: Data?, cleanup: () -> Void) {
		let fm = FileManager.default
		let xdgDirs = try BaseDirectories(prefixAll: "swift-sh")
		
		let scriptSource = try (
			!scriptPathIsContent ?
				ScriptSource(path: FilePath(scriptPathOrContent), fileManager: fm) :
				ScriptSource(content: scriptPathOrContent, fileManager: fm, logger: logger)
		)
		let cleanup = {
			if let scriptPath = scriptSource.scriptPath, scriptPath.isTmp {
				/* Notes:
				 * We should probably also register a sigaction to remove the temporary file in case of a terminating signal.
				 * Or we could remove the file just after launching swift with it (to be tested). */
				let p = scriptPath.0.string
				do    {try fm.removeItem(atPath: p)}
				catch {logger.warning("Failed removings temporary file.", metadata: ["file-path": "\(p)", "error": "\(error)"])}
			}
		}
		
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
		
		return (swiftArgs + [scriptPathForSwift], scriptData?.0, cleanup)
	}
	
}


fileprivate extension BuildAndRunOptions {
	
	var scriptPathIsContent: Bool {
		scriptOptions.scriptPathIsContent
	}
	
	var scriptPathOrContent: String {
		scriptOptions.scriptPathOrContent
	}
	
	var useSSHForGithubDependencies: Bool {
		scriptOptions.useSSHForGithubDependencies
	}
	
}
