import Foundation

import ProcessInvocation
import SystemPackage
import UnwrapOrThrow



/* The path to the script.
 * We assume arguments has its first argument properly set to the script’s path. */
public let scriptPath: FilePath = .init(CommandLine.arguments[0])
public let scriptFolderPath: FilePath = scriptPath.removingLastComponent()

public let scriptURL: URL = .init(filePath: scriptPath.string, directoryHint: .notDirectory)
public let scriptFolderURL: URL = .init(filePath: scriptFolderPath.string, directoryHint: .isDirectory)


public enum PathBase : Sendable {
	
	case scriptFolder
	case scriptRepoRoot
	
}

public func changeCurrentDirectoryPath(_ pathBase: PathBase? = nil, _ relativePath: FilePath? = nil) throws {
	let pathBase: FilePath = try {
		switch pathBase {
			case .scriptFolder?:
				return scriptFolderPath
				
			case .scriptRepoRoot?:
				var errOutput = ""
				var repoRootResult: Result<String, Error>?
				let pi = ProcessInvocation(
					"git", "rev-parse", "--show-toplevel",
					workingDirectory: !isBeingTested ? scriptFolderURL : URL(filePath: #filePath).deletingLastPathComponent(),
					stdinRedirect: .none(setFgPgID: false)
				)
				let (process, dispatchGroup) = try pi.invoke{ result, signalEndOfInterestForStream, process in
					do {
						let lineWithSource = try result.get()
						guard lineWithSource.fd == .standardOutput else {
							errOutput += lineWithSource.strLineOrHex() + "\n"
							return
						}
						if repoRootResult != nil {
							/* Only an empty line is acceptable here: git should output exactly a single line
							 *  (unless one of the path component contains a newline, but let’s not go there…). */
							guard lineWithSource.line.isEmpty, lineWithSource.eol.isEmpty else {
								throw MessageError("Cannot determine the root of the repository: git output was not a single line.")
							}
						} else {
							let line = try lineWithSource.strLine()
							repoRootResult = .success(line)
						}
					} catch {
						repoRootResult = .failure(error)
					}
				}
				process.waitUntilExit()
				/* TODO: We can have a priority inversion here because the QoS of the queue we’re waiting on is lower than user-initiated.
				 * Fix should probably be to run the queue at user-initiated level and potentially allow clients to set the QoS. */
				dispatchGroup.wait()
				
				let (exitStatus, exitReason) = (process.terminationStatus, process.terminationReason)
				guard exitStatus == 0, exitReason == .exit else {
					throw MessageError("Cannot determine the root of the repository: git failed. git stderr:\n\(errOutput)")
				}
				
				return FilePath(try repoRootResult?.get() ?! MessageError("Cannot determine the root of the repository: git did not output anything."))
				
			case nil:
				return "."
		}
	}()
	
	let newPath: FilePath =
		if let relativePath {pathBase.pushing(relativePath)}
		else                {pathBase}
	
	guard FileManager.default.changeCurrentDirectoryPath(newPath.string) else {
		throw MessageError("Failed setting current directory path to \(newPath.string).")
	}
}


/* For testing setting the current directory path from git repo root. */
internal nonisolated(unsafe) var isBeingTested: Bool = false
