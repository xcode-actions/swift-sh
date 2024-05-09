import Foundation

import ArgumentParser



final class ScriptOptions : ParsableArguments {
	
	@Flag(name: .long)
	var useSSHForGithubDependencies: Bool = false
	
	@Flag(name: .customShort("c"))
	var scriptPathIsContent = false
	
	@Argument
	var scriptPathOrContent: String = "-"
	
}
