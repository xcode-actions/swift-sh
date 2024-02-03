import Foundation
#if canImport(System)
import System
#else
import SystemPackage
#endif



extension FilePath {
	
	var url: URL {
		/* For now we do not consider Windows. */
#if !os(Linux)
		if #available(macOS 13.0, tvOS 16.0, iOS 16.0, watchOS 9.0, *) {
			return URL(filePath: string)
		} else {
			return URL(fileURLWithPath: string)
		}
#else
		return URL(fileURLWithPath: string)
#endif
	}
	
}
