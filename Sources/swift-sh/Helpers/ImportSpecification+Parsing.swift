import Foundation
import RegexBuilder

import Logging
import SystemPackage
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
		let blessedImport = "SwiftSH_Helpers"
		let whitespaces = OneOrMore{ .horizontalWhitespace }
		let maybeWhitespaces = ZeroOrMore{ .horizontalWhitespace }
		let importSpecifier = ChoiceOf{ "class"; "enum"; "struct"; "protocol"; "typealias"; "func"; "let"; "var" }
		
		/* Convenience function to convert a constraint match to a constraint. */
		func constraintFrom(constraintType: ConstraintType, constraintValue: String) -> Constraint? {
			if let constraintVersion = Version(tolerant: constraintValue) {
				switch constraintType {
					case .exact:         return .exact(constraintVersion)
					case .upToNextMajor: return .upToNextMajor(from: constraintVersion)
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
				return .ref(constraintValue)
			}
		}
		
		/* First let’s parse the import line with a comment next to it. */
		let moduleAndComment: (String, String?)? = {
			let moduleNameRef = Reference(Substring.self)
			let starCommentContentRef = Reference(String?.self)
			let doubleSlashCommentContentRef = Reference(String?.self)
			
			let starCommentRegex = Regex{
				"/*"
				maybeWhitespaces
				Capture(OneOrMore(.reluctant){ .any }, as: starCommentContentRef, transform: { String($0) })
				maybeWhitespaces
				"*/"
			}
			let doubleSlashCommentRegex = Regex{
				"//"
				maybeWhitespaces
				Capture(OneOrMore(.reluctant){ .any }, as: doubleSlashCommentContentRef, transform: { String($0) })
				maybeWhitespaces
				Anchor.endOfLine
			}
			let regex = Regex{
				Anchor.startOfLine
				maybeWhitespaces
				Optionally{ "@testable"; whitespaces }
				"import"; whitespaces
				Optionally{ importSpecifier; whitespaces }
				
				Capture(as: moduleNameRef){
					OneOrMore(.reluctant){ .any }
					Lookahead{ ChoiceOf{
						"."; "/";
						.horizontalWhitespace
						Anchor.endOfLine
					} }
				}
				/* Theoretically this part is only possible (and must be there) if the import specifier (class, enum, etc.) is present.
				 * To simplify, we’ll allow it always. */
				Optionally{
					"."; OneOrMore{ .whitespace.inverted }
				}
				
				maybeWhitespaces
				Optionally{
					ChoiceOf{
						starCommentRegex
						doubleSlashCommentRegex
					}
				}
			}
			/* Note: Not whole match because star comments can not match to the end of the line.
			 * Basically we ignore everything after the star comments. */
			guard let match = try? regex.firstMatch(in: line) else {
				return nil
			}
			
			let moduleName = String(match[moduleNameRef])
			
			let hasStarComment = (match[starCommentContentRef] != nil)
			let hasDoubleSlashComment = (match[doubleSlashCommentContentRef] != nil)
			guard hasStarComment || hasDoubleSlashComment else {
				return (moduleName, nil)
			}
			
			/* Exactly one of the two references must have matched. */
			assert(hasStarComment != hasDoubleSlashComment)
			return (moduleName, match[starCommentContentRef] ?? match[doubleSlashCommentContentRef]!)
		}()
		guard let (moduleName, commentContent) = moduleAndComment else {
			return nil
		}
		
		guard let commentContent else {
			/* If there are no comments, the only thing that we will still report as an import spec is the import of the helpers. */
			guard moduleName == blessedImport else {
				return nil
			}
			self = .init(
				moduleName: blessedImport,
				moduleSource: .github(user: "xcode-actions", repo: "swift-sh"),
				/* The Version init will fail in builds where the version has not been properly set in the SwiftSH struct. */
				constraint: Version(SwiftSH.configuration.version).flatMap{ .exact($0) } ?? .latest
			)
			return
		}
		
		/* Now parse the comment content. */
		let moduleSourceStrAndConstraint: (String?, Constraint?)? = {
			let moduleSourceRef = Reference(String?.self)
			let constraintTypeRef = Reference(ConstraintType?.self)
			let constraintValueRef = Reference(String?.self)
			let regex = Regex{
				Optionally(.reluctant){
					Capture(as: moduleSourceRef){ OneOrMore(.reluctant){ .any } }transform:{ String($0) }
				}
				maybeWhitespaces
				Optionally{
					Capture(as: constraintTypeRef){
						ChoiceOf{
							ConstraintType.exact.rawValue
							ConstraintType.upToNextMajor.rawValue
						}
					}transform:{ substr in ConstraintType(rawValue: String(substr))! }
					maybeWhitespaces
					Capture(as: constraintValueRef){ OneOrMore{ .any } }transform:{ String($0) }
				}
			}
			guard let match = try? regex.wholeMatch(in: commentContent) else {
				return nil
			}
			
			let moduleSource = match[moduleSourceRef]
			
			/* Either both refs should have matched, or none of them. */
			assert((match[constraintTypeRef] == nil) == (match[constraintValueRef] == nil))
			guard let constraintType  = match[constraintTypeRef],
					let constraintValue = match[constraintValueRef]
			else {
				guard let moduleSource else {
					return nil
				}
				return (moduleSource, nil)
			}
			guard let constraint = constraintFrom(constraintType: constraintType, constraintValue: constraintValue) else {
				return nil
			}
			return (moduleSource, constraint)
		}()
		guard let (moduleSourceStr, constraint) = moduleSourceStrAndConstraint else {
			return nil
		}
		
		guard let moduleSourceStr else {
			/* The only case where module origin can be nil is for SwiftSH_Helpers, because we _know_ its origin. */
			guard moduleName == blessedImport else {
				return nil
			}
			self = .init(
				moduleName: blessedImport,
				moduleSource: .github(user: "xcode-actions", repo: "swift-sh"),
				constraint: constraint ?? .latest /* We play it safe, but constraint cannot be nil here theoretically. */
			)
			return
		}
		
		guard let moduleSource = ModuleSource(moduleSourceStr, scriptFolder: scriptFolder, fileManager: fm, logger: logger) else {
			return nil
		}
		
		self = .init(moduleName: moduleName, moduleSource: moduleSource, constraint: constraint ?? .latest)
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
						logger.info("Cannot get home directory for user; dropping import spec.", metadata: ["username": "\(username)"])
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
