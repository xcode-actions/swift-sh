import Foundation

import ArgumentParser
import SystemPackage



extension FilePath.Component : @retroactive ExpressibleByArgument {
	
	public init?(argument: String) {
		self.init(argument)
	}
	
}
