import Foundation
#if canImport(System)
import System
#else
import SystemPackage
#endif

import ArgumentParser



extension FilePath : @retroactive ExpressibleByArgument {
	
	public init(argument: String) {
		self.init(argument)
	}
	
}
