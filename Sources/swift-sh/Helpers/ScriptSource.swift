import Foundation

import Logging
import SystemPackage
import UnwrapOrThrow



struct ScriptSource {
	
	let dataHandle: FileHandle
	
	let scriptName: String
	let scriptPath: (FilePath, isTmp: Bool)? /* nil if the source is non-replayable. */
	let scriptFolder: FilePath
	
	let initialAbsoluteScriptPath: FilePath?
	
	init(path: FilePath, fileManager fm: FileManager) throws {
		let (isStdinPlaceholder, isReplayable) = try Self.getPathInfo(path)
		self.scriptPath = (isReplayable ? (path, false) : nil)
		if isStdinPlaceholder {
			self.scriptName = "stdin"
			self.dataHandle = .standardInput
			self.scriptFolder = FilePath(fm.currentDirectoryPath)
			self.initialAbsoluteScriptPath = nil
		} else {
			self.scriptName = path.stem ?? "unknown"
			self.dataHandle = try FileHandle(forReadingFrom: path.url)
			self.scriptFolder = path.removingLastComponent()
			self.initialAbsoluteScriptPath = FilePath(fm.currentDirectoryPath).pushing(path)
		}
	}
	
	init(copying path: FilePath, fileManager fm: FileManager) throws {
		let destPath = Self.getTempFilePathPath(fileManager: fm)
		self.scriptPath = (destPath, true)
		self.scriptFolder = destPath.removingLastComponent()
		self.scriptName = try destPath.stem ?! InternalError(message: "no stem") /* Note this error should never happen due to the way destPath is built. */
		
		let isStdinPlaceholder = Self.isStdinPlaceholder(path)
		do {
			/* We open a do clause to have fh released at the end and the handle closed. */
			let fh: FileHandle = try (isStdinPlaceholder ? .standardInput : .init(forReadingFrom: path.url))
			let data = try fh.readToEnd() ?? Data()
			try data.write(to: destPath.url)
		}
		self.dataHandle = try FileHandle(forReadingFrom: destPath.url)
		self.initialAbsoluteScriptPath = isStdinPlaceholder ? nil : FilePath(fm.currentDirectoryPath).pushing(path)
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
			self.initialAbsoluteScriptPath = nil
		} catch {
			do    {try fm.removeItem(atPath: p)}
			catch {logger.warning("Failed removing temporary file.", metadata: ["file-path": "\(p)", "error": "\(error)"])}
			throw error
		}
	}
	
	private static func isStdinPlaceholder(_ path: FilePath) -> Bool {
		return path == "-"
	}
	
	private static func getPathInfo(_ path: FilePath) throws -> (isStdinPlaceholder: Bool, isReplayable: Bool) {
		guard !isStdinPlaceholder(path) else {
			return (true, false)
		}
		
		/* Let’s detect non-replayable content.
		 *
		 * A note about resolvingSymlinksInPath: it will drop the `/private` from the resolved link, if any, and if the result is an existing file.
		 * For instance, if the path is `/tmp`, which is a link to `/private/tmp`, the resulting path will still be `/tmp`.
		 * In practice that means that we won’t detect a directory was given in input if the input is `/tmp`, `/var`, etc.
		 * Does it matter? I think not.
		 * (We will still fail later, just with a more cryptic error.) */
		let resources = try URL(filePath: path.string).resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
		guard !(try resources.isDirectory ?! InternalError(message: "Cannot get input file directory info.")) else {
			struct InputIsDir : Error, CustomStringConvertible {
				var description: String {"Input file is a directory."}
			}
			throw InputIsDir()
		}
		
		let isRegularFile = try resources.isRegularFile ?! InternalError(message: "Cannot get input file regular file info.")
		return (false, isRegularFile)
	}
	
	private static func getTempFilePathPath(fileManager fm: FileManager) -> FilePath {
		var p: String
		repeat {
			p = fm.temporaryDirectory.appending(path: "swift-sh-inline-content-\(UUID().uuidString).swift", directoryHint: .notDirectory).path(percentEncoded: false)
		} while fm.fileExists(atPath: p)
		return FilePath(p)
	}
	
}
