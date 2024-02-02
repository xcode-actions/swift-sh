import Foundation
#if canImport(System)
import System
#else
import SystemPackage
#endif

import ArgumentParser
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
		let swiftArgs: [String] = if let depsPackage {
			try await depsPackage.retrieveREPLInvocation(
				packageFolder: xdgDirs.ensureCacheDirPath(FilePath("store").appending(depsPackage.packageHash.map{ String(format: "%02x", $0) }.joined())),
				disableSandboxForPackageResolution: disableSandboxForPackageResolution,
				fileManager: fm, logger: logger
			)
		} else {[]}
		
		let stdinForSwift: FileDescriptor
		if let data = scriptData {
			let pipe = try ProcessInvocation.unownedPipe()
			stdinForSwift = pipe.fdRead
			if data.0.count > 0 {
				let writtenRef = IntRef(value: 0)
				let fhWrite = FileHandle(fileDescriptor: pipe.fdWrite.rawValue)
				fhWrite.writeabilityHandler = { fh in
					data.0.withUnsafeBytes{ (bytes: UnsafeRawBufferPointer) in
						let writtenTotal: Int
						let writtenBefore = writtenRef.value
						
						let writtenNow = {
							var ret: Int
							repeat {
								ret = write(fh.fileDescriptor, bytes.baseAddress!.advanced(by: writtenBefore), bytes.count - writtenBefore)
							} while ret == -1 && errno == EINTR
							return ret
						}()
						if writtenNow >= 0 {
							writtenTotal = writtenNow + writtenBefore
							writtenRef.value = writtenTotal
						} else {
							if [EAGAIN, EWOULDBLOCK].contains(errno) {
								/* We ignore the write error and let the writeabilityHandler call us back (let’s hope it will!). */
								writtenTotal = writtenBefore
							} else {
								writtenTotal = -1
								logger.warning("Failed write end of fd for pipe to swift.", metadata: ["errno": "\(errno)", "errno-str": "\(Errno(rawValue: errno).localizedDescription)"])
							}
						}
						
						if bytes.count - writtenTotal <= 0 || writtenTotal == -1 {
							fhWrite.writeabilityHandler = nil
							if close(fh.fileDescriptor) == -1 {
								logger.warning("Failed closing write end of fd for pipe to swift.", metadata: ["errno": "\(errno)", "errno-str": "\(Errno(rawValue: errno).localizedDescription)"])
							}
						}
					}
				}
			} else {
				try pipe.fdWrite.close()
			}
		} else {
			stdinForSwift = .standardInput
		}
		
		let allArgs = swiftArgs + [scriptPathForSwift] + scriptArguments
		logger.trace("Running script.", metadata: ["invocation": .array((["swift"] + allArgs).map{ "\($0)" })])
		_ = try await ProcessInvocation(
			"swift", args: allArgs, usePATH: true,
			stdin: stdinForSwift, stdoutRedirect: .none, stderrRedirect: .none,
			signalHandling: { .mapForChild(for: $0, with: [.interrupt: .terminated]/* Swift eats the interrupts for some reasons… */) }
		).invokeAndGetRawOutput()
		
		if stdinForSwift != .standardInput {
			do    {try stdinForSwift.close()}
			catch {logger.warning("Failed closing read end of fd for pipe to swift.", metadata: ["error": "\(error)"])}
		}
	}
	
}


extension Run {
	
	fileprivate var logger: Logger {
		globalOptions.logger
	}
	
}


private class IntRef {
	
	var value: Int
	
	init(value: Int) {
		self.value = value
	}
	
}
