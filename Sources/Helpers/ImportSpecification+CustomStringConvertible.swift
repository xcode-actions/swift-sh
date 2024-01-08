import Foundation



extension ImportSpecification.ModuleSource : CustomStringConvertible {
	
	var description: String {
		switch self {
			case let .url(url):    return "ModuleSource.url(\(url))"
			case let .scp(source): return "ModuleSource.scp(\(source))"
			case let .local(path): return "ModuleSource.local(\(path))"
			case let .github(user, repo): return "ModuleSource.github(\(user), \(repo ?? "nil"))"
		}
	}
	
}


extension ImportSpecification.Constraint : CustomStringConvertible {
	
	var description: String {
		switch self {
			case let .upToNextMajor(version): return "Constraint.upToNextMajor(\(version))"
			case let .exact(version):         return "Constraint.exact(\(version))"
			case let .ref(ref):               return "Constraint.ref(\(ref))"
			case     .latest:                 return "Constraint.latest"
		}
	}
	
}
