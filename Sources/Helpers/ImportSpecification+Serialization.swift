import Foundation
import RegexBuilder
#if canImport(System)
import System
#else
import SystemPackage
#endif

import Logging
import UnwrapOrThrow
import Version



extension ImportSpecification {
	
	func packageDependencyLine(useSSHForGithubDependencies: Bool) -> String {
		let githubPrefix = (!useSSHForGithubDependencies ? "https://github.com/" : "git@github.com:")
		switch moduleSource {
			case let .local(path, scriptFolder): return #".package(path: "\#((scriptFolder?.pushing(path) ?? path).string.escaped())")"#
			case let .scp(scpDescr):             return #".package(url: "\#(scpDescr.escaped())", "#                                                    + "\(constraint.forPackageLine()))"
			case let .url(url):                  return #".package(url: "\#(url.absoluteString.escaped())", "#                                          + "\(constraint.forPackageLine()))"
			case let .github(user, repo):        return #".package(url: "\#(githubPrefix)\#(user.escaped())/\#((repo ?? moduleName).escaped()).git", "# + "\(constraint.forPackageLine()))"
		}
	}
	
	func targetDependencyLine() -> String {
#warning("TODO: scp case.")
		switch moduleSource {
			case let .local(path, _):  return #".product(name: "\#(moduleName.escaped())", package: "\#((path.stem?.description ?? moduleName).escaped())")"#
			case let .scp(scpDescr):   return #".product(name: "\#(moduleName.escaped())", package: "\#(moduleName.escaped())")"#
			case let .url(url):        return #".product(name: "\#(moduleName.escaped())", package: "\#(url.deletingPathExtension().lastPathComponent.escaped())")"#
			case let .github(_, repo): return #".product(name: "\#(moduleName.escaped())", package: "\#((repo ?? moduleName).escaped())")"#
		}
	}
	
}


extension ImportSpecification.Constraint {
	
	func forPackageLine() -> String {
		switch self {
			case let .upToNextMajor(v): return #"from: "\#(v.description.escaped())""#
			case let .exact(v):         return #"revision: "\#(v.description.escaped())""# /* Note: We use “revision”, not “exact” on purpose (allows using packages who themselves have dependencies on a specific revision). */
			case let .ref(ref):         return #"revision: "\#(ref.escaped())""#
			case .latest:               return "Version(0,0,0)...Version(1_000_000,0,0)" /* Hacky… from original swift-sh from mxcl. */
		}
	}
	
}
