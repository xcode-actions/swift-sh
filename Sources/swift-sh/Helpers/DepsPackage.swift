import Foundation
#if canImport(System)
import System
#else
import SystemPackage
#endif
import RegexBuilder

import Crypto
import Logging
import ProcessInvocation
import StreamReader



struct DepsPackage {
	
	/* A hash that can be used to check whether two DepsPackages are the same.
	 * This should be used to set the path in which the REPL invocation retrieval should be done from. */
	let packageHash: Data
	private let packageSwiftContent: Data
	
	/* Returns nil if no package is needed (skipPackageOnNoRemoteModules && no remote package). */
	init?(scriptSource: ScriptSource, scriptData: inout (Data, hash: Data)?, useSSHForGithubDependencies: Bool, skipPackageOnNoRemoteModules: Bool, fileManager fm: FileManager, logger: Logger) throws {
		/* Let’s parse the source file.
		 * We’re doing a very bad job at parsing, but that’s mostly on purpose. */
		var importSpecs = [ImportSpecification]()
		var hasher = (scriptData != nil ? Insecure.MD5() : nil)
		let streamReader = FileHandleReader(stream: scriptSource.dataHandle, bufferSize: 3 * 1024, bufferSizeIncrement: 1024, underlyingStreamReadSizeLimit: 1)
		while let (lineData, eolData) = try streamReader.readLine() {
//			logger.trace("Received new source line data.", metadata: ["line-data": "\(lineData.reduce("", { $0 + String(format: "%02x", $1) }))"])
			scriptData?.0.append(lineData); hasher?.update(data: lineData)
			scriptData?.0.append(eolData);  hasher?.update(data: eolData)
			
			guard let lineStr = String(data: lineData, encoding: .utf8) else {
				/* We ignore non-UTF8 lines.
				 * There should be none (valid UTF8 is a requirement for Swift files),
				 *  but if we find any it’s not our job to reject them. */
				continue
			}
			
			if (try? #/(^|\s)@main(\s|$)/#.firstMatch(in: lineStr)) != nil {
				logger.warning("""
					Possible @main detected.
					@main is not supported (yet?) in scripts, so you have to call the main directly.
					If you are using ArgumentParser’s AsyncParsableCommand, you can call the main like so:
					   _ = await Task{ await YourMainType.main() }.value
					""")
			}
			
			logger.trace("Parsing new source line for import specification.", metadata: ["line": "\(lineStr)"])
			guard let importSpec = ImportSpecification(line: lineStr, scriptFolder: scriptSource.scriptFolder, fileManager: fm, logger: logger) else {
				continue
			}
			logger.debug("Found new import specification.", metadata: ["import-spec": "\(importSpec)", "line": "\(lineStr)"])
			importSpecs.append(importSpec)
		}
		hasher.flatMap{ scriptData?.hash = Data($0.finalize()) }
		
		guard !importSpecs.isEmpty || !skipPackageOnNoRemoteModules else {
			return nil
		}
		
		self.packageSwiftContent = Self.packageSwiftContentWith(importSpecifications: importSpecs, useSSHForGithubDependencies: useSSHForGithubDependencies)
		self.packageHash = Data(SHA256.hash(data: packageSwiftContent))
	}
	
	func retrieveREPLInvocation(packageFolder: FilePath, buildDependenciesInReleaseMode: Bool, disableSandboxForPackageResolution: Bool, fileManager fm: FileManager, logger: Logger) async throws -> [String] {
		/* Let’s see if we need to update/create the Package.swift file. */
		let packageSwiftPath = packageFolder.appending("Package.swift")
		let packageSwiftURL = packageSwiftPath.url
		let emptyFilePath = packageFolder.appending("empty.swift")
		let needsPackageUpdate = try !fm.fileExists(atPath: packageSwiftPath.string) || {
			/* The file exists. Do we need to update it? */
			if try Data(contentsOf: packageSwiftURL) != packageSwiftContent {
				return true
			}
			/* If the content is the same, we may want to update the file anyway if it was modified more than some time ago.
			 * We do this to force SPM to update the package if needed (not sure it works though). */
			let properties = try packageSwiftURL.resourceValues(forKeys: [.contentModificationDateKey])
			return (properties.contentModificationDate ?? .distantPast).timeIntervalSinceNow < -7*24*60*60/* 7 days */
		}()
		if needsPackageUpdate {
			try packageSwiftContent.write(to: packageSwiftURL)
		}
		if !fm.fileExists(atPath: emptyFilePath.string) {
			try Data().write(to: emptyFilePath.url)
		}
		
		/* Note: openpty is more or less deprecated and we should use the more complex but POSIX compliant way to open the PTY.
		 * See relevant test in swift-process-invocation for more info. */
		var slaveRawFd: Int32 = 0
		var masterRawFd: Int32 = 0
		guard openpty(&masterRawFd, &slaveRawFd, nil/*name*/, nil/*termp*/, nil/*winp*/) == 0 else {
			struct CannotOpenTTYError : Error {var errmsg: String}
			throw CannotOpenTTYError(errmsg: Errno(rawValue: errno).localizedDescription)
		}
		/* Note: No defer in which we close the fds, they will be closed by ProcessInvocation. */
		let slaveFd = FileDescriptor(rawValue: slaveRawFd)
		let masterFd = FileDescriptor(rawValue: masterRawFd)
		let pi = ProcessInvocation(
			"swift", args: ["run", "--repl"] + (buildDependenciesInReleaseMode ? ["-c", "release"] : []) + (disableSandboxForPackageResolution ? ["--disable-sandbox"] : []),
			usePATH: true, workingDirectory: packageFolder.url,
			/* The environment below tricks swift somehow into allowing the REPL when stdout is not a tty.
			 * We do one better and give it a pty directly and we know we’re good. */
//			environment: ["PATH": "/Applications/Xcode.app/Contents/Developer/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin", "NSUnbufferedIO": "YES"],
			stdinRedirect: .fromNull, stdoutRedirect: .toFd(slaveFd, giveOwnership: true), stderrRedirect: .capture, additionalOutputFileDescriptors: [masterFd],
			lineSeparators: .newLine(unix: true, legacyMacOS: false, windows: true/* Because of the pty, I think. */),
			expectedTerminations: [(0, .exit), (9, .uncaughtSignal)/* For some unknown reason, in GitHub Actions, swift ends properly but is reported as having been killed with uncaught signal 9. */]
		)
		var ret: [String]?
		var errorOutput = [String]()
		do {
			for try await lineWithSource in pi {
				switch lineWithSource.fd {
					case masterFd:
						/* This is interesting to us.
						 * Let’s try and detect the REPL arguments. */
						logger.debug("swift stdout: \(lineWithSource.strLineOrHex())")
						guard let line = try? lineWithSource.strLine() else {
							logger.warning("Got non-utf8 line output on stdout from swift.", metadata: ["line-as-hex": "\(lineWithSource.strLineOrHex())"])
							continue
						}
						let regex = Regex{
							OneOrMore{ .any }; ": repl "; Capture{ OneOrMore{ .any } }
						}
						guard let capture = try? regex.wholeMatch(in: line)?.output.1 else {
							logger.debug("Ignored non-repl-matching output on stdout from swift.", metadata: ["line": "\(line)"])
							continue
						}
						if let ret {
							logger.warning("Got multiple lines matching repl args; taking the last one.", metadata: ["current-match": "\(ret.joined(separator: " "))"])
						}
						let newRet = capture.split(separator: " ").map(String.init)
						if (
							!newRet.contains(where: { $0.hasPrefix("-I") }) ||
							!newRet.contains(where: { $0.hasPrefix("-L") }) ||
							!newRet.contains(where: { $0.hasPrefix("-l") })
						) {
							logger.notice("Suspicious REPL args found.", metadata: ["args": "\(newRet.joined(separator: " "))"])
						}
						ret = newRet
						
					case .standardError:
						logger.debug("swift stderr: \(lineWithSource.strLineOrHex())")
						errorOutput.append(lineWithSource.strLineOrHex())
						
					default:
						logger.warning("Got line from unknown fd from swift.", metadata: ["fd": "\(lineWithSource.fd)", "line-or-hex": "\(lineWithSource.strLineOrHex())"])
				}
			}
		} catch ProcessInvocationError.unexpectedSubprocessExit(let terminationStatus, let terminationReason) {
			/* Even if we succeed in getting something we deliberately fail as the swift command failed.
			 * We catch the error because we want to have something less harsh than just
			 *  `Error: unexpectedSubprocessExit(terminationStatus: 1, terminationReason: __C.NSTaskTerminationReason)` in swift-sh output. */
			logger.warning("swift invocation for finding REPL args failed with unexpected subprocess exit.", metadata: ["termination_status": "\(terminationStatus)", "termination_reason": "\(terminationReason.rawValue)"])
			ret = nil
		}
		guard var ret else {
			struct CannotFindREPLArgs : Error {var swiftStderr: String}
			throw CannotFindREPLArgs(swiftStderr: errorOutput.joined(separator: "\n"))
		}
		/* Now swift has given us the arguments it thinks are needed to start the script.
		 * Spoiler: they are not enough!
		 * - When the deps contain an xcframework dependency, we have to add the -I option for swift to find the headers of the frameworks.
		 * - Starting w/ Swift 6, the arguments given by the REPL invocation give an incorrect include search path: we must add `/Modules` to the include path.
		 *   We check whether the `Modules` folder exists and add it to the command-line if it does.
		 *   Previously we added it the modified version unconditionally for each -I arguments,
		 *    but if both versions are present we get compilation errors for some dependencies (for ArgumentParser for instance).
		 * - For some dependencies that have a system library target, the path to the module.modulemap of the target should be added. */
		/* Add `/Modules` variants import options for Swift 6. */
		var idx = 0
		while idx < ret.count {
			defer {idx += 1}
			let (path, hasDashI): (String, Bool)
			if ret[idx] == "-I" {
				idx += 1
				guard idx < ret.count else {
					break
				}
				path = ret[idx]
				hasDashI = false
			} else if ret[idx].hasPrefix("-I") {
				path = String(ret[idx].dropFirst(2))
				hasDashI = true
			} else {
				continue
			}
			
			var isDir = ObjCBool(false)
			let pathWithModules = String(path.reversed().drop(while: { $0 == "/" }).reversed()) + "/Modules"
			if fm.fileExists(atPath: pathWithModules, isDirectory: &isDir) && isDir.boolValue {
				ret[idx] = (hasDashI ? "-I" : "") + pathWithModules
			}
		}
		/* Add xcframework import options. */
		let artifactsFolder = packageFolder.appending(".build/artifacts")
		if let directoryEnumerator = fm.enumerator(at: artifactsFolder.url, includingPropertiesForKeys: nil) {
			while let url = directoryEnumerator.nextObject() as! URL? {
				/* These rules are ad-hoc and work in the case I tested (an XcodeTools dependency).
				 * There are probably many cases where they won’t work. */
				let isXcframework = url.deletingLastPathComponent().deletingLastPathComponent().pathExtension == "xcframework"
				let isMacOS = url.deletingLastPathComponent().lastPathComponent.lowercased().hasPrefix("macos-")
				let isFramework = url.pathExtension == "framework"
				let isHeaders = url.lastPathComponent.lowercased() == "headers"
				if isXcframework && isMacOS {
					if isFramework {
						ret.append("-I\(url.absoluteURL.path)/Headers")
						directoryEnumerator.skipDescendants()
					} else if isHeaders {
						ret.append("-I\(url.absoluteURL.path)")
						directoryEnumerator.skipDescendants()
					}
				}
			}
		}
		/* Add module.modulemap in the source code checkouts that are “[system]”.
		 * Note there is probably a much better way of doing this, but I don’t know it. */
		let checkoutFolder = packageFolder.appending(".build/checkouts")
		if let directoryEnumerator = fm.enumerator(at: checkoutFolder.url, includingPropertiesForKeys: nil) {
			while let url = directoryEnumerator.nextObject() as! URL? {
				/* These rules are ad-hoc and work in the case I tested (an XcodeTools dependency).
				 * There are probably many cases where they won’t work. */
				if url.lastPathComponent.lowercased() == "module.modulemap",
					try String(contentsOf: url, encoding: .utf8).contains("[system]")
				{
					ret.append("-I\(url.deletingLastPathComponent().absoluteURL.path)")
					directoryEnumerator.skipDescendants()
				}
			}
		}
		return ret
	}
	
	private static func packageSwiftContentWith(importSpecifications: [ImportSpecification], useSSHForGithubDependencies: Bool) -> Data {
		let platforms: String = {
#if os(macOS)
			let version = ProcessInfo.processInfo.operatingSystemVersion
			if version.majorVersion <= 10 {
				return "[.macOS(.v\(version.majorVersion)_\(version.minorVersion))]"
			} else {
				/* We cap at macOS 13
				 *  which is the latest version available for Swift 5.7
				 *  which is the version we use in our generated Package.swift file. */
				return "[.macOS(.v\(min(13, version.majorVersion)))]"
			}
#else
			return "nil"
#endif
		}()
		return Data(#"""
			// swift-tools-version:5.7
			import PackageDescription
			
			
			let package = Package(
				name: "SwiftSH_DummyDepsPackage",
				platforms: \#(platforms),
				products: [.library(name: "SwiftSH_Deps", targets: ["SwiftSH_DummyDepsLib"])],
				dependencies: [
					\#(importSpecifications.map{ $0.packageDependencyLine(useSSHForGithubDependencies: useSSHForGithubDependencies) }.joined(separator: ",\n\t\t"))
				],
				targets: [
					.target(name: "SwiftSH_DummyDepsLib", dependencies: [
						\#(importSpecifications.map{ $0.targetDependencyLine() }.joined(separator: ",\n\t\t\t"))
					], path: ".", sources: ["empty.swift"])
				]
			)
			
			"""#.utf8)
	}
	
}
