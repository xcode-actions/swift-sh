import Foundation

import SystemPackage



extension FilePath {
	
	var url: URL {
		return URL(fileURLWithPath: string)
	}
	
}
