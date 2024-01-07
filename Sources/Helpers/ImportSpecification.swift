import Foundation
import RegexBuilder

import UnwrapOrThrow
import Version



public struct ImportSpecification : Equatable {
	
	let moduleName: String
	let moduleSource: ModuleSource
	let constraint: Constraint
	
	enum ModuleSource : Equatable {
		
		case url(URL)
		case local(String)
		case github(user: String, repo: String)
		
		init?(_ url: URL) {
			guard !url.absoluteString.isEmpty else {
				return nil
			}
#warning("TODO")
			self = .url(url)
		}
		
	}
	
	enum Constraint : Equatable {
		
		case upToNextMajor(from: Version)
		case exact(Version)
		case ref(String)
		case latest
		
	}
	
}


extension ImportSpecification {
	
	public init?(line: String) {
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
				One(.url(scheme: .optional, user: .optional, password: .optional,
							host: .optional, port: .optional, path: .required,
							query: .optional, fragment: .optional))
			}transform:{ url in try ModuleSource(url) ?! DummyError() }
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
					/* Maybe TODO: Log warning invalid constraint type was found for a ref. */
					return nil
				}
				self.constraint = .ref(constraintValue)
			}
		} else {
			self.constraint = .latest
		}
	}
	
}
