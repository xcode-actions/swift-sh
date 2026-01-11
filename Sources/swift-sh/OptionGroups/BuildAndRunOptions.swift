import Foundation

import ArgumentParser
import Crypto
import Logging
import SystemPackage
import UnwrapOrThrow
import XDG



final class BuildAndRunOptions : ParsableArguments {
	
	@Flag(name: .long, inversion: .prefixedNo)
	var skipPackageOnNoRemoteModules = true
	
	@Flag(name: .long, inversion: .prefixedNo)
	var buildDependenciesInReleaseMode = true
	
	@Flag(name: .long, inversion: .prefixedNo)
	var disableSandboxForPackageResolution = false
	
	@Option(name: .long)
	var swiftPath: FilePath = "swift"
	
	@OptionGroup
	var scriptOptions: ScriptOptions
	
	/* Returns the arguments that should be given to swift to run the script. */
	func prepareRun(forBuilding: Bool = false, logger: Logger) async throws -> (swiftArgs: [String], swiftFileToRun: String, swiftStdin: Data?, packageFolderPath: FilePath?, cleanup: () -> Void) {
		let fm = FileManager.default
		let xdgDirs = try BaseDirectories.swiftSH.get()
		
		let scriptSource = try (
			!scriptPathIsContent ?
				(
					forBuilding ?
						ScriptSource(copying: FilePath(scriptPathOrContent), fileManager: fm) :
						ScriptSource(path:    FilePath(scriptPathOrContent), fileManager: fm)
				) :
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
		var scriptData: Data?
		var scriptHash: Data?
		if let scriptPath = scriptSource.scriptPath {
			scriptData = nil
			/* Regarding the need for the scriptHash when the script path is the content:
			 *  it is only needed because we will use the hash of the contents of the script as the marker name for this script. */
			scriptHash = scriptPathIsContent ? Data() : nil
			scriptPathForSwift = scriptPath.0.string
		} else {
			scriptData = Data()
			scriptHash = Data()
			scriptPathForSwift = "-"
		}
		
		let depsPackage = try DepsPackage(
			scriptSource: scriptSource, scriptData: &scriptData, scriptHash: &scriptHash,
			useSSHForGithubDependencies: useSSHForGithubDependencies,
			skipPackageOnNoRemoteModules: skipPackageOnNoRemoteModules,
			fileManager: fm, logger: logger
		)
		
		let (swiftArgs, packageFolderPath): ([String], FilePath?) = try await {
			guard let depsPackage else {
				return ([String](), nil)
			}
			/* Retrieve the REPL invocation in package folder path.
			 * Note: This is not protected with regard to multiple scripts trying to use the same store entry.
			 * TODO: Make the REPL invocation retrieval concurrent-safe. */
			let packageFolderRelativePath = try xdgDirs.storeFolderRelativePath(for: depsPackage.packageHash)
			let packageFolderPath = try xdgDirs.ensureCacheDirPath(packageFolderRelativePath)
			let ret = try await depsPackage.retrieveREPLInvocation(
				packageFolder: packageFolderPath,
				buildDependenciesInReleaseMode: buildDependenciesInReleaseMode,
				disableSandboxForPackageResolution: disableSandboxForPackageResolution,
				fileManager: fm, logger: logger
			)
			
			if !forBuilding {
				/* If retrieving the REPL invocation was successful and we’re not building, we mark the store entry as being used.
				 * This is only for clients and has no use for swift-sh itself (allows light cleaning of the cache folder).
				 * Note: We are not concurrent-safe for this either. */
				do {
					let packageFolderAliasPath = try xdgDirs.ensureParentsForMarkerPathWith(
						absoluteScriptPath: scriptSource.initialAbsoluteScriptPath,
						nonReplayableScriptDataHash: scriptHash,
						hashFunction: Insecure.MD5.self
					)
					try? fm.removeItem(at: packageFolderAliasPath.url)
					/* Do not use the URL variant of this method as it is not possible (AFAICT) to create a relative link with it. */
					try fm.createSymbolicLink(atPath: packageFolderAliasPath.string, withDestinationPath: FilePath("..").appending(packageFolderRelativePath.components).string)
				} catch {
					logger.warning("Failed to create marker link in swift-sh cache.", metadata: ["error": "\(error)"])
				}
			}
			return (ret, packageFolderPath)
		}()
		
		return (swiftArgs, scriptPathForSwift, scriptData, packageFolderPath, cleanup)
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
