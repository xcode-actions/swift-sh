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
	
	init?(line: String, scriptFolder: FilePath, fileManager fm: FileManager, logger: Logger) {
		/* Temporary helper structures for the parsing. */
		struct DummyError : Error {}
		enum ConstraintType : String, CustomStringConvertible {
			case exact = "==", upToNextMajor = "~>"
			var description: String {rawValue}
		}
		
		/* Some conveniences. */
		let whitespace = OneOrMore{ .horizontalWhitespace }
		let maybeWhitespace = ZeroOrMore{ .horizontalWhitespace }
		
		/* References we will use in the regex. */
		let moduleNameRef = Reference(Substring.self)
		let moduleOriginRef = Reference(ModuleSource.self)
		let constraintTypeRef = Reference(ConstraintType?.self)
		let constraintValueRef = Reference(String?.self)
		let moduleOriginAndConstraintForSlashStarRef = Reference(String?.self)
		let moduleOriginAndConstraintForDoubleSlashRef = Reference(String?.self)
		
		/* Sub-regexes. */
		let moduleOriginRegex = Regex{
			Capture(as: moduleOriginRef){
				OneOrMore{ .whitespace.inverted }
			}transform:{ substr in try ModuleSource(String(substr), scriptFolder: scriptFolder, fileManager: fm, logger: logger) ?! DummyError() }
		}
		let constraintRegex = Regex{
			Capture(as: constraintTypeRef){
				ChoiceOf{
					ConstraintType.exact.rawValue
					ConstraintType.upToNextMajor.rawValue
				}
			}transform:{ substr in ConstraintType(rawValue: String(substr))! }
			maybeWhitespace
			Capture(as: constraintValueRef){
				OneOrMore{ .whitespace.inverted }
			}transform:{ substr in String(substr) }
		}
		let moduleOriginAndConstraintsRegex = Regex{
			maybeWhitespace
			moduleOriginRegex
			maybeWhitespace
			Optionally{
				constraintRegex
			}
			maybeWhitespace
		}
		
		/* Finally, the full regex. */
		let fullRegex = Regex{
			Anchor.startOfLine
			maybeWhitespace
			Optionally{ "@testable"; whitespace }
			"import"; whitespace
			Optionally{ ChoiceOf{ "class"; "enum"; "struct" }; whitespace }
			
			Capture(as: moduleNameRef){ OneOrMore{ ChoiceOf{ .word; "_" } } }
			/* Theoretically this part is only possible (and must be there) if the class/enum/struct modifier is present.
			 * To simplify, we’ll allow it always. */
			Optionally{
				"."; OneOrMore{ .whitespace.inverted }
			}
			
			maybeWhitespace
			ChoiceOf{
				Regex{
					"/*"
					Capture(moduleOriginAndConstraintsRegex, as: moduleOriginAndConstraintForSlashStarRef, transform: { String($0) })
					"*/"
				}
				Regex{
					"//"
					Capture(moduleOriginAndConstraintsRegex, as: moduleOriginAndConstraintForDoubleSlashRef, transform: { String($0) })
					Anchor.endOfLine
				}
			}
		}
		/* Let’s try and match this.
		 * We do a double-pass match because it is clearer than having two variables for the module origin, constraint type and constraint value.
		 * Instead we have two variables for the full “module origin and constraints” match, which we re-match later.
		 * Indeed this is not efficient, but it is efficient _enough_. */
		guard let match1 = try? fullRegex.firstMatch(in: line) else {
			/* If the match failed, we check the special case of the import of SwiftSH_Helpers.
			 * This package does not need to have an import specification: we _know_ them already.
			 * The regex is not perfect (it’s a regex), but it’ll do for our use case. */
			if (try? #/(^|;)(\s*@testable)?\s*import(\s+(class|enum|struct))?\s+SwiftSH_Helpers(\.[^\s]+)?/#.firstMatch(in: line)) != nil {
				self.moduleName = "SwiftSH_Helpers"
				self.moduleSource = .github(user: "xcode-actions", repo: "swift-sh")
				/* The Version init should never fail but we fallback to .latest if it were to fail… */
				self.constraint = Version(SwiftSH.configuration.version).flatMap{ .exact($0) } ?? .latest
				return
			}
			if (try? #/^(\s*@testable)?\s*import(\s+(class|enum|struct))?\s+[\w_]+(\.[^\s]+)?\s+(//|/*)/#.firstMatch(in: line)) != nil {
				logger.notice("Found a line starting with import followed by a comment that failed to match an import spec.", metadata: ["line": "\(line)"])
			}
			return nil
		}
		/* Exactly one of the two reference must have matched. */
		assert((match1[moduleOriginAndConstraintForSlashStarRef] == nil) != (match1[moduleOriginAndConstraintForDoubleSlashRef] == nil))
		let moduleOriginAndConstraints = (match1[moduleOriginAndConstraintForSlashStarRef] ?? match1[moduleOriginAndConstraintForDoubleSlashRef])!
		
		/* Now let’s match the moduleOriginAndConstraints against its regex. */
		let match2 = try! moduleOriginAndConstraintsRegex.wholeMatch(in: moduleOriginAndConstraints)!
		/* If the type matched, the value must have, and vice-versa. */
		assert((match2[constraintTypeRef] == nil) == (match2[constraintValueRef] == nil))
		
		self.moduleName = String(match1[moduleNameRef])
		self.moduleSource = match2[moduleOriginRef]
		if let constraintType = match2[constraintTypeRef], let constraintValue = match2[constraintValueRef] {
			if let constraintVersion = Version(tolerant: constraintValue) {
				switch constraintType {
					case .exact:         self.constraint = .exact(constraintVersion)
					case .upToNextMajor: self.constraint = .upToNextMajor(from: constraintVersion)
				}
			} else {
				guard constraintType == .exact else {
					logger.warning("Invalid constraint found with a non-exact type but a non-compliant version.", metadata: [
						"line": "\(line)",
						"constraint-type": "\(constraintType)",
						"constraint-value": "\(constraintValue)"
					])
					return nil
				}
				self.constraint = .ref(constraintValue)
			}
		} else {
			self.constraint = .latest
		}
	}
	
}


extension ImportSpecification.ModuleSource {
	
	/* TODO: Make this safe, I guess…
	 * Technically I’m pretty sure we never access this variable concurrently, but the compiler ain’t happy (and I’m not sure).
	 * For now let’s take the easy way out. */
	static nonisolated(unsafe) var hasLoggedObsoleteFormatWarning = false
	
	init?(_ stringToParse: String, scriptFolder: FilePath, fileManager fm: FileManager, logger: Logger) {
		/* Let’s try multiple formats until we find one that work. */
		do {
			/* We try the "@GitHubUsername" format first. */
			let usernameRef = Reference(Substring.self)
			let repoRef = Reference(String?.self)
			let regex = Regex{
				"@"
				Capture(as: usernameRef){ #/[a-zA-Z0-9-]+/# }
				Optionally{
					"/"
					Capture(as: repoRef){ #/[a-zA-Z0-9._-]+?/# }transform:{ substr in String(substr) }
					Optionally{ ".git" }
				}
			}
			if let match = try? regex.wholeMatch(in: stringToParse) {
				self = .github(user: String(match[usernameRef]), repo: match[repoRef])
				return
			}
		}
		do {
			/* Next we try the “scp” format.
			 * We do a lot of assumptions for this format:
			 *   - we assume only [a-zA-Z0-9] is valid in a username.
			 *   - we assume only [a-zA-Z0-9.-] is valid in a domain.
			 *   - we assume only [a-zA-Z0-9._/-] is valid in a path. */
			if (try? #/[a-zA-Z0-9]+@[a-zA-Z0-9.-]+:[a-zA-Z0-9._/-]+/#.wholeMatch(in: stringToParse)) != nil {
				self = .scp(stringToParse)
				return
			}
		}
		do {
			/* Next format to try is the legacy “github-username/repo-name” format.
			 * mxcl used that format for an unknown reason, but I prefer "@github-username/repo-name". */
			let usernameRef = Reference(Substring.self)
			let repoRef = Reference(Substring.self)
			let regex = Regex{
				/* Note: Same as in first format tested, but repoRef is not optional. */
				Capture(as: usernameRef){ #/[a-zA-Z0-9-]+/# }
				"/"
				Capture(as: repoRef){ #/[a-zA-Z0-9._-]+?/# }
				Optionally{ ".git" }
			}
			if let match = try? regex.wholeMatch(in: stringToParse) {
				if !Self.hasLoggedObsoleteFormatWarning {
					logger.notice(#"The “github-username/repo-name” format is deprecated; please use "@github-username/repo-name" instead."#)
					Self.hasLoggedObsoleteFormatWarning = true
				}
				self = .github(user: String(match[usernameRef]), repo: String(match[repoRef]))
				return
			}
		}
		guard let url = URL(string: stringToParse) else {
			return nil
		}
		if url.scheme != nil {
			self = .url(url)
		} else {
			/* We assume a local path for everything that do not have a scheme and has not the specific formats above. */
			var path = stringToParse
			let usernameRef = Reference(String?.self)
			let regex = Regex{
				Anchor.startOfLine
				"~"
				Optionally{
					Capture(as: usernameRef){ #/[^/]+/# }transform:{ substr in String(substr) }
				}
			}
			if let match = try? regex.firstMatch(in: path) {
				let home: FilePath
				if let username = match[usernameRef] {
					guard let homeDir = fm.homeDirectory(forUser: username) else {
						logger.warning("Cannot get home directory for user.", metadata: ["username": "\(username)"])
						return nil
					}
					home = FilePath(homeDir.path)
				} else {
					home = FilePath(fm.homeDirectoryForCurrentUser.path)
				}
				path.replaceSubrange(match.range, with: home.string)
			}
			self = .local(.init(path), scriptFolder: scriptFolder)
		}
	}
	
}
