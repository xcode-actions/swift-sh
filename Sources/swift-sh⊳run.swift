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
				if (try? #/^(\s*@testable)?\s*import(\s+(class|enum|struct))?\s+[\w_]+(\.[^\s]+)?\s+(//|/*)/#.firstMatch(in: lineStr)) != nil {
					logger.notice("Found a line starting with import followed by a comment that failed to match an import spec.", metadata: ["line": "\(lineStr)"])
				}
				continue
			}
			logger.debug("Found new import specification.", metadata: ["import-spec": "\(importSpec)", "line": "\(lineStr)"])
		}
		
		let scriptAbsolutePath = (!isStdin ? FilePath(fm.currentDirectoryPath).pushing(scriptPath) : "")
		let scriptName = (!isStdin ? (scriptPath.stem ?? "unknown") : "stdin")
		let scriptHash = (Insecure.MD5.hash(data: !isStdin ? Data(scriptAbsolutePath.string.utf8) : stdinData))
		let scriptHashStr = scriptHash.reduce("", { $0 + String(format: "%02x", $1) })
		let cacheDir = try xdgDirs.ensureCacheDirPath(FilePath("\(scriptName)-\(scriptHashStr)"))
		
		let packageSwiftContent = #"""
			// swift-tools-version:5.7
			import PackageDescription
			
			
			let package = Package(
				name: "SwiftSH_DummyDepsPackage",
				platforms: [
					.macOS(.v13)
				],
				products: [
					.library(name: "SwiftSH_Deps", targets: ["SwiftSH_DummyDepsLib"])
				],
				dependencies: [
					.package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
					.package(url: "https://github.com/Frizlab/UnwrapOrThrow.git",       from: "1.0.1-rc"),
					.package(url: "https://github.com/Frizlab/swift-xdg.git",           from: "1.0.0-beta"),
					.package(url: "https://github.com/mxcl/LegibleError.git",           from: "1.0.0"),
					.package(url: "https://github.com/mxcl/Version.git",                from: "2.0.0"),
					.package(url: "https://github.com/xcode-actions/clt-logger.git",    from: "0.8.0"),
					.package(url: "https://github.com/xcode-actions/stream-reader.git", from: "3.5.0"),
					.package(url: "https://github.com/xcode-actions/XcodeTools.git",    revision: "0.9.1"),
				],
				targets: [
					.library(name: "SwiftSH_DummyDepsLib", dependencies: [
						.product(name: "ArgumentParser", package: "swift-argument-parser"),
						.product(name: "CLTLogger",      package: "clt-logger"),
						.product(name: "LegibleError",   package: "LegibleError"),
						.product(name: "StreamReader",   package: "stream-reader"),
						.product(name: "UnwrapOrThrow",  package: "UnwrapOrThrow"),
						.product(name: "Version",        package: "Version"),
						.product(name: "XcodeTools",     package: "XcodeTools"),
						.product(name: "XDG",            package: "swift-xdg"),
					], path: ".", sources: ["empty.swift"])
				]
			)
			"""#
	}
	
}


extension Run {
	
	fileprivate var logger: Logger {
		globalOptions.logger
	}
	
}
