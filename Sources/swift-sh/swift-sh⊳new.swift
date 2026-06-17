import Foundation

import ArgumentParser
import Logging
import SystemPackage



/* Command that creates a new script with the given name.
 * Basically it’s a “copy template” command… */
struct New : AsyncParsableCommand {
	
	@OptionGroup
	var globalOptions: GlobalOptions
	
	enum SwiftExtensionGeneration : EnumerableFlag {
		case none, addIfNeeded
		static func name(for value: Self) -> NameSpecification {
			switch value {
				case .none:        return [.customLong( "no-swift-extension"), .customShort("b")]
				case .addIfNeeded: return [.customLong("add-swift-extension")]
			}
		}
	}
	@Flag
	var addSwiftExtensionIfNeeded: SwiftExtensionGeneration = .addIfNeeded
	
	@Flag(inversion: .prefixedEnableDisable, help: "Whether allowing overwrite of an existing file is allowed.")
	var overwrite: Bool = false
	
	@Argument(help: """
		The path to the new script.
		The `.swift` extension is added to the path if not already there,
		 unless the `--no-swift-extension` (or `-b`) option is set.
		The parent folder of the given path must exist.
		""")
	var scriptPath: FilePath
	
	func run() async throws {
		logger.error("Not implemented")
		throw ExitCode(1)
	}
	
}


extension New {
	
	fileprivate var logger: Logger {
		globalOptions.logger
	}
	
}
