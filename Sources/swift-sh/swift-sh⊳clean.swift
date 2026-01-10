import Foundation

import ArgumentParser
import Crypto
import InlineObjectConfig
import Logging
import SystemPackage
import XDG



struct Clean : AsyncParsableCommand {
	
	@OptionGroup
	var globalOptions: GlobalOptions
	
	@Flag(name: .long, inversion: .prefixedNo)
	var endByCleaningUnused: Bool = true
	
	@Argument(
		help: """
			What to clean.
			
			This can either be the path to a script or one of the special targets: `unused`, `ephemeral` and `all`.
			(If you want to clean for a script that has the same name as a special target, prefix the script path by `./`.)
			
			The `unused` target will clean all cache that is not used by any script anymore.
			Such cache can exist when a script’s dependency changes: the old cache is not removed.
			
			The `ephemeral` target will clean the markers for ephemeral scripts (`-c` option, from stdin, etc.).
			It will not however clean the actual cache that was used by those markers.
			You should also clean the unused to get those cleaned (automatically added unless endByCleaningUnused is set to false).
			
			The `all` target will clean all of swift-sh’s cache.
			
			Cleaning the cache for a given script, will only remove the marker for such script (just like for the ephemeral target).
			To remove the actual cache, you should also add the unused target.
			""",
		/* We do not provide completion for unused and all, because I do not want to rewrite the file completion logic…
		 * Also, if a file named “all” exists, both `./all` and `all` should be proposed. */
		completion: .file(extensions: ["swift", "swift-sh", ""])
	)
	fileprivate var targets: [CleaningTarget] = [.ephemeral]
	
	func run() async throws {
		let fullTargets = targets--{ targets in
			if endByCleaningUnused, targets.last != .unused {
				targets.append(.unused)
			}
			if targets.contains(.all) {
				targets = [.all]
			}
		}
		
		let fm = FileManager.default
		let xdgDirs = try BaseDirectories.swiftSH.get()
		for target in fullTargets {
			switch target {
				case .all:
					let cacheFolder = xdgDirs.cacheHomePrefixed
					try fm.removeIfExistsWithLog(cacheFolder, logger: logger)
					
				case .ephemeral:
					let markersFolderPath = try xdgDirs.markersFolderPath()
					/* TODO: Implement this. */
					
				case .unused:
					let storeFolderPath = try xdgDirs.storeFolderPath()
					let markersFolderPath = try xdgDirs.markersFolderPath()
					/* TODO: Implement this. */
					
				case .script(let path):
					let path = FilePath(fm.currentDirectoryPath).pushing(path)
					let cachePath = try xdgDirs.markerPathWith(absoluteScriptPath: path, nonReplayableScriptDataHash: nil, hashFunction: Insecure.MD5.self)
					try fm.removeIfExistsWithLog(cachePath, logger: logger)
			}
		}
	}
	
}


private enum CleaningTarget : ExpressibleByArgument, Equatable {
	
	case all
	case unused
	case ephemeral
	case script(FilePath)
	
	init?(argument: String) {
		switch argument {
			case "all":       self = .all
			case "unused":    self = .unused
			case "ephemeral": self = .ephemeral
			case "-":         self = .script(.init(argument))
			default:          self = .script(.init(argument))
		}
	}
	
}


fileprivate extension Clean {
	
	var logger: Logger {
		globalOptions.logger
	}
	
}
