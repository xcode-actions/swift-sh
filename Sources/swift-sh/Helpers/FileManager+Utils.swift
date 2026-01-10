import Foundation

import Logging
import SystemPackage



extension FileManager {
	
	func removeIfExistsWithLog(_ filePath: FilePath, logger: Logger) throws {
		guard fileExists(atPath: filePath.string) else {
			return
		}
		logger.notice("Removing file or folder.", metadata: ["path": "\(FilePath(currentDirectoryPath).pushing(filePath).lexicallyNormalized().string)"])
		try removeItem(at: filePath.url)
	}
	
}
