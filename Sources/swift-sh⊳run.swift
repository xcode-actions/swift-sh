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
		
		let isStdin: Bool
		let isTemporary: Bool
		let scriptPath: String
		if !scriptPathIsContent {
			/* Note: Our stdin detection probably lacks a lot of edge cases but we deem it enough, at least for now. */
			/* TODO: The case of named pipes… */
			isTemporary = false
			scriptPath = scriptPathOrContent
			isStdin = (scriptPath == "-" || scriptPath == "/dev/stdin")
		} else {
			/* To do the `-c` option, we have to create a temporary file and delete it when we’re done.
			 * This is due to swift not supporting the `-c` option, or an equivalent (AFAICT). */
			var p: String
			repeat {
#if canImport(Darwin)
				p = fm.temporaryDirectory.appending(path: "swift-sh-dash-c-content-\(UUID().uuidString).swift", directoryHint: .notDirectory).path
#else
				p = fm.temporaryDirectory.appendingPathComponent("swift-sh-dash-c-content-\(UUID().uuidString).swift").path
#endif
			} while fm.fileExists(atPath: p)
			guard fm.createFile(atPath: p, contents: Data(scriptPathOrContent.utf8), attributes: [.posixPermissions: 0o400]) else {
				struct CannotCreateTempFile : Error {var path: String}
				throw CannotCreateTempFile(path: p)
			}
			scriptPath = p
			isStdin = false
			isTemporary = true
		}
		defer {
			if isTemporary {
				/* Notes:
				 * We should probably also register a sigaction to remove the temporary file in case of a terminating signal.
				 * Or we could remove the file just after launching swift with it (to be tested). */
				if (try? fm.removeItem(atPath: scriptPath)) == nil {
					logger.warning("Failed removing temporary file.", metadata: ["path": "\(scriptPath)"])
				}
			}
		}
		logger.debug("Running script", metadata: ["script-path": "\(!isStdin ? scriptPath : "<stdin>")", "script-arguments": .array(scriptArguments.map{ "\($0)" })])
		
		let depsPackage = try DepsPackage(scriptPath: FilePath(scriptPath), isStdin: isStdin, xdgDirs: xdgDirs, fileManager: fm, logger: logger)
		let swiftArgs = try await depsPackage.retrieveREPLInvocation(
			skipPackageOnNoRemoteModules: skipPackageOnNoRemoteModules,
			useSSHForGithubDependencies: globalOptions.useSSHForGithubDependencies,
			disableSandboxForPackageResolution: disableSandboxForPackageResolution,
			fileManager: fm,
			logger: logger
		)
		
		let stdinForSwift: FileDescriptor
		if let data = depsPackage.stdinScriptData {
			let pipe = try ProcessInvocation.unownedPipe()
			stdinForSwift = pipe.fdRead
			if data.count > 0 {
				let writtenRef = IntRef(value: 0)
				let fhWrite = FileHandle(fileDescriptor: pipe.fdWrite.rawValue)
				fhWrite.writeabilityHandler = { fh in
					data.withUnsafeBytes{ (bytes: UnsafeRawBufferPointer) in
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
		
		logger.trace("Running script.", metadata: ["invocation": .array((["swift"] + swiftArgs + [scriptPath] + scriptArguments).map{ "\($0)" })])
		_ = try await ProcessInvocation(
			"swift", args: swiftArgs + [scriptPath] + scriptArguments, usePATH: true,
			stdin: stdinForSwift, stdoutRedirect: .none, stderrRedirect: .none,
			signalHandling: { .mapForChild(for: $0, with: [.interrupt: .terminated]/* Swift eats the interrupts for some reasons… */) }
		).invokeAndGetRawOutput()
		
		if stdinForSwift != .standardInput {
			if (try? stdinForSwift.close()) == nil {
				logger.warning("Failed closing read end of fd for pipe to swift.")
			}
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
