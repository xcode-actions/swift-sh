import Crypto
import Foundation
#if canImport(System)
import System
#else
import SystemPackage
#endif

import ArgumentParser
import Logging
import StreamReader
import XcodeTools
import XDG



struct Run : AsyncParsableCommand {
	
	@OptionGroup
	var globalOptions: GlobalOptions
	
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
		
		let fh: FileHandle
		if !isStdin {fh = try FileHandle(forReadingFrom: scriptPath.url)}
		else        {fh =     FileHandle.standardInput}
		defer {try? fh.close()} /* Is it bad if we close stdin? I don’t think so, but maybe we should think about it… */
		
		/* Let’s parse the source file.
		 * We’re doing a very bad job at parsing, but that’s mostly on purpose. */
		var stdinData = Data() /* We only keep the file contents when we’re reading from stdin. */
		var importSpecs = [ImportSpecification]()
		let streamReader = FileHandleReader(stream: fh, bufferSize: 3 * 1024, bufferSizeIncrement: 1024)
		while let (lineData, newLineData) = try streamReader.readLine() {
//			logger.trace("Received new source line data.", metadata: ["line-data": "\(lineData.reduce("", { $0 + String(format: "%02x", $1) }))"])
			if isStdin {
				stdinData.append(lineData)
				stdinData.append(newLineData)
			}
			
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
		
		let scriptAbsolutePath = (!isStdin ? FilePath(fm.currentDirectoryPath).pushing(scriptPath) : "")
		let scriptFolder = (!isStdin ? scriptAbsolutePath.removingLastComponent() : FilePath(fm.currentDirectoryPath))
		let scriptName = (!isStdin ? (scriptPath.stem ?? "unknown") : "stdin")
		let scriptHash = (Insecure.MD5.hash(data: !isStdin ? Data(scriptAbsolutePath.string.utf8) : stdinData))
		let scriptHashStr = scriptHash.reduce("", { $0 + String(format: "%02x", $1) })
		let cacheDir = try xdgDirs.ensureCacheDirPath(FilePath("\(scriptName)-\(scriptHashStr)"))
		
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
					\#(importSpecs.map{ $0.packageDependencyLine(scriptFolder: scriptFolder) }.joined(separator: ",\n\t\t"))
				],
				targets: [
					.library(name: "SwiftSH_DummyDepsLib", dependencies: [
						\#(importSpecs.map{ $0.targetDependencyLine() }.joined(separator: ",\n\t\t\t"))
					], path: ".", sources: ["empty.swift"])
				]
			)
			"""#
		print(packageSwiftContent)
	}
	
}


extension Run {
	
	fileprivate var logger: Logger {
		globalOptions.logger
	}
	
}
