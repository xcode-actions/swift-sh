import Foundation

import Crypto
import SystemPackage
import UnwrapOrThrow
import XDG



extension BaseDirectories {
	
	static let swiftSH: Result<BaseDirectories, Error> = .init{ try BaseDirectories(prefixAll: "swift-sh") }
	
	func storeFolderRelativePath(for packageHash: Data? = nil) throws -> FilePath {
		let component = try packageHash.map{
			try FilePath.Component($0.reduce("", { $0 + String(format: "%02x", $1) })) ?! InternalError(message: "Hash reduced to hex did not give a path component.")
		}
		return Self.storeFolderPath.appending(component.map{ [$0] } ?? [])
	}
	
	func storeFolderPath(for packageHash: Data? = nil) throws -> FilePath {
		try cacheFilePath(for: storeFolderRelativePath(for: packageHash))
	}
	
	func ensureStoreFolderPath(for packageHash: Data? = nil) throws -> FilePath {
		try ensureCacheDirPath(storeFolderRelativePath(for: packageHash))
	}
	
	func markersFolderPath() throws -> FilePath {
		return try cacheFilePath(for: Self.markersFolderPath)
	}
	
	func markerPathWith<H : HashFunction>(
		absoluteScriptPath: FilePath?,
		nonReplayableScriptDataHash: Data?,
		hashFunction: H.Type 
	) throws -> FilePath {
		return try cacheFilePath(for: Self.markerRelativePathWith(
			absoluteScriptPath: absoluteScriptPath,
			nonReplayableScriptDataHash: nonReplayableScriptDataHash,
			hashFunction: hashFunction
		))
	}
	
	/* Returns the path to the marker (not its parent). */
	func ensureParentsForMarkerPathWith<H : HashFunction>(
		absoluteScriptPath: FilePath?,
		nonReplayableScriptDataHash: Data?,
		hashFunction: H.Type /* The hash function that was (or would be) used for hashing the script data. */
	) throws -> FilePath {
		return try ensureCacheDirPath(Self.markerRelativePathWith(
			absoluteScriptPath: absoluteScriptPath,
			nonReplayableScriptDataHash: nonReplayableScriptDataHash,
			hashFunction: hashFunction
		))
	}
	
	private static let   storeFolderPath: FilePath = "store"
	private static let markersFolderPath: FilePath = "markers"
	
	private static func markerRelativePathWith<H : HashFunction>(
		absoluteScriptPath: FilePath?,
		nonReplayableScriptDataHash: Data?,
		hashFunction: H.Type
	) throws -> FilePath {
		assert(absoluteScriptPath != nil || nonReplayableScriptDataHash != nil)
		let markerName = {
			let hashString = (nonReplayableScriptDataHash ?? Data(H.hash(data: Data(absoluteScriptPath!.lexicallyNormalized().string.utf8))))
				.reduce("", { $0 + String(format: "%02x", $1) })
			if nonReplayableScriptDataHash != nil {
				/* If the input file is non-replayable, we do not care to store it’s name, we only store the content’s hash in the key. */
				return hashString
			} else {
				/* Here nonReplayableScriptDataHash is nil, which means absoluteScriptPath is not (asserted), */
				let absoluteScriptPath = absoluteScriptPath!
				return "\(absoluteScriptPath.stem ?? "unknown")--\(hashString)"
			}
		}()
		return Self.markersFolderPath.appending(markerName)
	}
	
}
