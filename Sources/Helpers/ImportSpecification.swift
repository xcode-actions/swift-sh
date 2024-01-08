import Foundation
import Logging
import RegexBuilder
#if canImport(System)
import System
#else
import SystemPackage
#endif

import UnwrapOrThrow
import Version



struct ImportSpecification : Equatable {
	
	enum ModuleSource : Equatable {
		
		case url(URL)
		case scp(String)
		case local(FilePath)
		case github(user: String, repo: String?) /* If repo is nil, the module name should be used. */
		
	}
	
	enum Constraint : Equatable {
		
		case upToNextMajor(from: Version)
		case exact(Version)
		case ref(String)
		case latest
		
	}
	
	let moduleName: String
	let moduleSource: ModuleSource
	let constraint: Constraint
	
}
