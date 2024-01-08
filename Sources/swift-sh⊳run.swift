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
			guard let importSpec = ImportSpecification(line: lineStr) else {
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
	}
	
}


extension Run {
	
	fileprivate var logger: Logger {
		globalOptions.logger
	}
	
}
