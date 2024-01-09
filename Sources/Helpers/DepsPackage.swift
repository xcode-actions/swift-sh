import Crypto
import Foundation
#if canImport(System)
import System
#else
import SystemPackage
#endif
import RegexBuilder

import Logging
import StreamReader
import XcodeTools
import XDG



struct DepsPackage {
	
	let rootPath: FilePath
	let scriptFolder: FilePath
	let importSpecifications: [ImportSpecification]
	
	init(scriptPath: FilePath, isStdin: Bool, xdgDirs: BaseDirectories, fileManager fm: FileManager, logger: Logger) throws {
		let fh: FileHandle
		if !isStdin {fh = try FileHandle(forReadingFrom: scriptPath.url)}
		else        {fh =     FileHandle.standardInput}
		defer {try? fh.close()} /* Is it bad if we close stdin? I don’t think so, but maybe we should think about it… */
		
		/* Let’s parse the source file.
		 * We’re doing a very bad job at parsing, but that’s mostly on purpose. */
		var importSpecs = [ImportSpecification]()
		var stdinData: Data? = (isStdin ? Data() : nil) /* We only keep the file contents when we’re reading from stdin. */
		let streamReader = FileHandleReader(stream: fh, bufferSize: 3 * 1024, bufferSizeIncrement: 1024)
		while let (lineData, newLineData) = try streamReader.readLine() {
//			logger.trace("Received new source line data.", metadata: ["line-data": "\(lineData.reduce("", { $0 + String(format: "%02x", $1) }))"])
			stdinData?.append(lineData)
			stdinData?.append(newLineData)
			
			guard let lineStr = String(data: lineData, encoding: .utf8) else {
				/* We ignore non-UTF8 lines.
				 * There should be none (valid UTF8 is a requirement for Swift files),
				 *  but if we find any it’s not our job to reject them. */
				continue
			}
			
			logger.trace("Parsing new source line.", metadata: ["line": "\(lineStr)"])
			guard let importSpec = ImportSpecification(line: lineStr, fileManager: fm) else {
				continue
			}
			logger.debug("Found new import specification.", metadata: ["import-spec": "\(importSpec)", "line": "\(lineStr)"])
			importSpecs.append(importSpec)
		}
		self.importSpecifications = importSpecs
		
		let scriptAbsolutePath = (!isStdin ? FilePath(fm.currentDirectoryPath).pushing(scriptPath) : "")
		let scriptFolder = (!isStdin ? scriptAbsolutePath.removingLastComponent() : FilePath(fm.currentDirectoryPath))
		let scriptName = (!isStdin ? (scriptPath.stem ?? "unknown") : "stdin")
		let scriptHash = (Insecure.MD5.hash(data: stdinData ?? Data(scriptAbsolutePath.string.utf8)))
		let scriptHashStr = scriptHash.reduce("", { $0 + String(format: "%02x", $1) })
		/* TODO: Technically the line below is a side-effect and should be avoided at all cost in an init method… */
		self.rootPath = try xdgDirs.ensureCacheDirPath(FilePath("\(scriptName)-\(scriptHashStr)"))
		self.scriptFolder = scriptFolder
	}
	
	func retrieveREPLInvocation(skipPackageOnNoRemoteModules: Bool, fileManager fm: FileManager, logger: Logger) async throws -> [String] {
		guard !importSpecifications.isEmpty || !skipPackageOnNoRemoteModules else {
			return []
		}
		
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
		let packageSwiftContent = #"""
			// swift-tools-version:5.7
			import PackageDescription
			
			
			let package = Package(
				name: "SwiftSH_DummyDepsPackage",
				platforms: \#(platforms),
				products: [.library(name: "SwiftSH_Deps", targets: ["SwiftSH_DummyDepsLib"])],
				dependencies: [
					\#(importSpecifications.map{ $0.packageDependencyLine(scriptFolder: scriptFolder) }.joined(separator: ",\n\t\t"))
				],
				targets: [
					.target(name: "SwiftSH_DummyDepsLib", dependencies: [
						\#(importSpecifications.map{ $0.targetDependencyLine() }.joined(separator: ",\n\t\t\t"))
					], path: ".", sources: ["empty.swift"])
				]
			)
			"""#
		
		/* Let’s see if we need to update/create the Package.swift file. */
		let packageSwiftPath = rootPath.appending("Package.swift")
		let packageSwiftURL = packageSwiftPath.url
		let emptyFilePath = rootPath.appending("empty.swift")
		let needsPackageUpdate = try !fm.fileExists(atPath: packageSwiftPath.string) || {
			/* The file exists. Do we need to update it? */
			let contents = try Data(contentsOf: packageSwiftURL)
			if contents != Data(packageSwiftContent.utf8) {
				return true
			}
			/* If the content is the same, we may want to update the file anyway if it was modified more than some time ago.
			 * We do this to force SPM to update the package if needed (not sure if works though). */
			let properties = try packageSwiftURL.resourceValues(forKeys: [.contentModificationDateKey])
			return (properties.contentModificationDate ?? .distantPast).timeIntervalSinceNow < -3*60*60
		}()
		if needsPackageUpdate {
			try packageSwiftContent.write(to: packageSwiftURL, atomically: false, encoding: .utf8)
		}
		if !fm.fileExists(atPath: emptyFilePath.string) {
			try Data().write(to: emptyFilePath.url)
		}
		
		let pi = ProcessInvocation(
			"swift", "run", "-c", "release", "--repl",
			usePATH: true, workingDirectory: rootPath.url,
			stdin: nil, stdoutRedirect: .capture, stderrRedirect: .capture
		)
		var ret: [String]?
		var errorOutput = [String]()
		do {
			for try await lineWithSource in pi {
				switch lineWithSource.fd {
					case .standardOutput:
						/* This is interesting to us.
						 * Let’s try and detect the REPL arguments. */
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
						errorOutput.append(lineWithSource.strLineOrHex())
						
					default:
						logger.warning("Got line from unknown fd from swift.", metadata: ["fd": "\(lineWithSource.fd)", "line-or-hex": "\(lineWithSource.strLineOrHex())"])
				}
			}
		} catch XcodeToolsError.unexpectedSubprocessExit {
			/* Even if we succeed in getting something we deliberately fail as the swift command failed.
			 * We catch the error because we want to have something less harsh than just
			 *  `Error: unexpectedSubprocessExit(terminationStatus: 1, terminationReason: __C.NSTaskTerminationReason)` in swift-sh output. */
			ret = nil
		}
		guard let ret else {
			struct CannotFindREPLArgs : Error {var swiftStderr: String}
			throw CannotFindREPLArgs(swiftStderr: errorOutput.joined(separator: "\n"))
		}
		return ret
	}
	
}
