import Foundation

import ArgumentParser
import SystemPackage



extension FilePath : @retroactive ExpressibleByArgument {
	
	public init(argument: String) {
		self.init(argument)
	}
	
}
