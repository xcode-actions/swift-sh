import Foundation
import Logging
#if canImport(System)
import System
#else
import SystemPackage
#endif

import UnwrapOrThrow
import Version



struct ImportSpecification {
	
	enum ModuleSource {
		
		case url(URL)
		case scp(String)
		case local(FilePath, scriptFolder: FilePath?)
		case github(user: String, repo: String?) /* If repo is nil, the module name should be used. */
		
	}
	
	enum Constraint {
		
		case upToNextMajor(from: Version) /* "~>" followed by a version */
		case exact(Version)               /* "==" followed by a version */
		case ref(String)                  /* "==" followed by not a version */
		case latest                       /* nothing */
		
	}
	
	let moduleName: String
	let moduleSource: ModuleSource
	let constraint: Constraint
	
}
