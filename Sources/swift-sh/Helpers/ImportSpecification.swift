import Foundation

import Logging
import SystemPackage
import UnwrapOrThrow
import Version



struct ImportSpecification {
	
	enum ModuleSource : Equatable {
		
		case url(URL)
		case scp(String)
		case local(FilePath, scriptFolder: FilePath?)
		case github(user: String, repo: String?) /* If repo is nil, the module name should be used. */
		
	}
	
	enum Constraint : Equatable {
		
		case upToNextMajor(from: Version) /* "~>" followed by a version */
		case exact(Version)               /* "==" followed by a version */
		case ref(String)                  /* "==" followed by not a version */
		case latest                       /* nothing */
		
	}
	
	let moduleName: String
	let moduleSource: ModuleSource
	let constraint: Constraint
	
}
