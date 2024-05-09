import Foundation
#if canImport(System)
import System
#else
import SystemPackage
#endif

import Logging
import UnwrapOrThrow



struct ScriptSource {
	
	let dataHandle: FileHandle
	
	let scriptName: String
	let scriptPath: (FilePath, isTmp: Bool)? /* nil if the source is non-replayable. */
	let scriptFolder: FilePath
	
	init(path: FilePath, fileManager fm: FileManager) throws {
		let (pathRepresentsStdin, isReplayable) = Self.getPathInfo(path)
		self.scriptPath = (isReplayable ? (path, false) : nil)
		if pathRepresentsStdin {
			self.scriptName = "stdin"
			self.dataHandle = .standardInput
			self.scriptFolder = FilePath(fm.currentDirectoryPath)
		} else {
			self.scriptName = path.stem ?? "unknown"
			self.dataHandle = try FileHandle(forReadingFrom: path.url)
			self.scriptFolder = path.removingLastComponent()
		}
	}
	
	init(copying path: FilePath, fileManager fm: FileManager) throws {
		let destPath = Self.getTempFilePathPath(fileManager: fm)
		self.scriptPath = (destPath, true)
		self.scriptFolder = destPath.removingLastComponent()
		self.scriptName = try destPath.stem ?! InternalError(message: "no stem") /* Note this error should never happen due to the way destPath is built. */
		
		let (pathRepresentsStdin, _) = Self.getPathInfo(path)
		do {
			/* We open a do clause to have fh released at the end and the handle closed. */
			let fh: FileHandle = try (pathRepresentsStdin ? .standardInput : .init(forReadingFrom: path.url))
			let data = try fh.readToEnd() ?? Data()
			try data.write(to: destPath.url)
		}
		self.dataHandle = try FileHandle(forReadingFrom: destPath.url)
	}
	
	init(content: String, fileManager fm: FileManager, logger: Logger) throws {
		/* To do the `-c` option, we have to create a temporary file and delete it when we’re done.
		 * This is due to swift not supporting the `-c` option, or an equivalent (AFAICT). */
		let p = Self.getTempFilePathPath(fileManager: fm).string
		guard fm.createFile(atPath: p, contents: Data(content.utf8), attributes: [.posixPermissions: 0o400]) else {
			struct CannotCreateTempFile : Error {var path: String}
			throw CannotCreateTempFile(path: p)
		}
		do {
			self.scriptPath = (FilePath(p), true)
			self.scriptName = "inline-content"
			self.dataHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: p))
			self.scriptFolder = FilePath(fm.currentDirectoryPath)
		} catch {
			do    {try fm.removeItem(atPath: p)}
			catch {logger.warning("Failed removing temporary file.", metadata: ["file-path": "\(p)", "error": "\(error)"])}
			throw error
		}
	}
	
	private static func getPathInfo(_ path: FilePath) -> (representsStdin: Bool, isReplayable: Bool) {
		let pathRepresentsStdin = (path == "-")
		/* TODO: Proper detection of non replayable content…
		 * For now we only detect (badly) stdin, but there are a lot of non-replayable content! */
		let isReplayable = (!pathRepresentsStdin && path != "/dev/stdin")
		return (pathRepresentsStdin, isReplayable)
	}
	
	private static func getTempFilePathPath(fileManager fm: FileManager) -> FilePath {
		var p: String
		repeat {
#if canImport(Darwin)
			p = fm.temporaryDirectory.appending(path: "swift-sh-inline-content-\(UUID().uuidString).swift", directoryHint: .notDirectory).path
#else
			p = fm.temporaryDirectory.appendingPathComponent("swift-sh-inline-content-\(UUID().uuidString).swift").path
#endif
		} while fm.fileExists(atPath: p)
		return FilePath(p)
	}
	
	private struct InternalError : Error {var message: String}
	
}
