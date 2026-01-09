import Foundation
import SystemPackage
import Testing

import Logging
import Version

@testable import swift_sh


struct ImportSpecificationUnitTests {
	
	let fileManager = FileManager.default
	let logger = Logger(label: "com.xcode-actions.swift-sh-tests.ImportSpecificationUnitTests")
	
	let cwdPath  = FilePath(FileManager.default.currentDirectoryPath)
	let homePath = FilePath(FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false))
	
	@Test
	func testWigglyArrow() throws {
		let parsed = try #require(ImportSpecification(line: "import Foo // @mxcl ~> 1.0", scriptFolder: cwdPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "Foo")
		#expect(parsed.moduleSource == .github(user: "mxcl", repo: nil))
		#expect(parsed.constraint == .upToNextMajor(from: .one))
	}
	
	@Test
	func testTrailingWhitespace() throws {
		let parsed = try #require(ImportSpecification(line: "import Foo // @mxcl ~> 1.0 ", scriptFolder: cwdPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "Foo")
		#expect(parsed.moduleSource == .github(user: "mxcl", repo: nil))
		#expect(parsed.constraint == .upToNextMajor(from: .one))
	}
	
	@Test
	func testExact() throws {
		let parsed = try #require(ImportSpecification(line: "import Foo // @mxcl == 1.0", scriptFolder: cwdPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "Foo")
		#expect(parsed.moduleSource == .github(user: "mxcl", repo: nil))
		#expect(parsed.constraint == .exact(.one))
	}
	
	@Test
	func testMoreSpaces() throws {
		let parsed = try #require(ImportSpecification(line: "import    Foo       //     @mxcl    ~>      1.0", scriptFolder: cwdPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "Foo")
		#expect(parsed.moduleSource == .github(user: "mxcl", repo: nil))
		#expect(parsed.constraint == .upToNextMajor(from: .one))
	}
	
	@Test
	func testMinimalSpaces() throws {
		let parsed = try #require(ImportSpecification(line: "import Foo//@mxcl~>1.0", scriptFolder: cwdPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "Foo")
		#expect(parsed.moduleSource == .github(user: "mxcl", repo: nil))
		#expect(parsed.constraint == .upToNextMajor(from: .one))
	}
	
	@Test
	func testCanOverrideImportName() throws {
		let parsed = try #require(ImportSpecification(line: "import Foo  // @mxcl/Bar ~> 1.0", scriptFolder: cwdPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "Foo")
		#expect(parsed.moduleSource == .github(user: "mxcl", repo: "Bar"))
		#expect(parsed.constraint == .upToNextMajor(from: .one))
	}
	
	@Test
	func testCanOverrideImportNameLegacyFormat() throws {
		let parsed = try #require(ImportSpecification(line: "import Foo  // mxcl/Bar ~> 1.0", scriptFolder: cwdPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "Foo")
		#expect(parsed.moduleSource == .github(user: "mxcl", repo: "Bar"))
		#expect(parsed.constraint == .upToNextMajor(from: .one))
	}
	
	@Test
	func testCanOverrideImportNameUsingNameWithHyphen() throws {
		let parsed = try #require(ImportSpecification(line: "import Bar  // @mxcl/swift-bar ~> 1.0", scriptFolder: cwdPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "Bar")
		#expect(parsed.moduleSource == .github(user: "mxcl", repo: "swift-bar"))
		#expect(parsed.constraint == .upToNextMajor(from: .one))
	}
	
	@Test
	func testCanProvideLocalPath() throws {
		let parsed = try #require(ImportSpecification(line: "import Bar  // \(homePath.string)", scriptFolder: homePath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "Bar")
		#expect(parsed.moduleSource == .local(homePath, scriptFolder: homePath))
		#expect(parsed.packageDependencyLine(useSSHForGithubDependencies: false) == #".package(path: "\#(homePath.string)")"#)
	}
	
	@Test
	func testCanProvideLocalPathWithTilde() throws {
		let parsed = try #require(ImportSpecification(line: "import Bar  // ~/", scriptFolder: homePath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "Bar")
		#expect(parsed.moduleSource == .local(homePath, scriptFolder: homePath))
		#expect(parsed.packageDependencyLine(useSSHForGithubDependencies: false) == #".package(path: "\#(homePath.string)")"#)
	}
	
	@Test
	func testCanProvideLocalRelativeCurrentPath() throws {
		let parsed = try #require(ImportSpecification(line: "import Bar  // ./", scriptFolder: cwdPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "Bar")
		#expect(parsed.moduleSource == .local(".", scriptFolder: cwdPath))
		#expect(parsed.packageDependencyLine(useSSHForGithubDependencies: false) == #".package(path: "\#(cwdPath.string)/.")"#)
	}
	
	@Test
	func testCanProvideLocalRelativeNonCurrentPath() throws {
		/* Provide a script path that’s inside the home directory (not cwd). */
		let parsed = try #require(ImportSpecification(line: "import Bar  // ./", scriptFolder: homePath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "Bar")
		#expect(parsed.moduleSource == .local(".", scriptFolder: homePath))
		#expect(parsed.packageDependencyLine(useSSHForGithubDependencies: false) == #".package(path: "\#(homePath.string)/.")"#)
	}
	
	@Test
	func testCanProvideLocalRelativeParentPath() throws {
		let cwdParent = cwdPath.appending("..")
		let parsed = try #require(ImportSpecification(line: "import Bar  // ../", scriptFolder: cwdPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "Bar")
		#expect(parsed.moduleSource == .local("..", scriptFolder: cwdPath))
		#expect(parsed.packageDependencyLine(useSSHForGithubDependencies: false) == #".package(path: "\#(cwdParent.string)")"#)
	}
	
	@Test
	func testCanProvideLocalRelativeTwoParentsUpPath() throws {
		let cwdParent = cwdPath.appending("..").appending("..")
		let parsed = try #require(ImportSpecification(line: "import Bar  // ../../", scriptFolder: cwdPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "Bar")
		#expect(parsed.moduleSource == .local("../..", scriptFolder: cwdPath))
		#expect(parsed.packageDependencyLine(useSSHForGithubDependencies: false) == #".package(path: "\#(cwdParent.string)")"#)
	}
	
	@Test
	func testCanProvideLocalPathWithHypen() throws {
		let tmpPath = FilePath("/tmp/fake/with-hyphen-two/lastone")
		/* Original test created the directory, because it must have checked the dependency actually exists, but we do not (and IMHO should not). */
		//try fileManager.createDirectory(at: URL(filePath: tmpPath.string, directoryHint: .isDirectory), withIntermediateDirectories: true)
		let parsed = try #require(ImportSpecification(line: "import Foo  // /tmp/fake/with-hyphen-two/lastone", scriptFolder: tmpPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "Foo")
		#expect(parsed.moduleSource == .local(tmpPath, scriptFolder: tmpPath))
		#expect(parsed.packageDependencyLine(useSSHForGithubDependencies: false) == #".package(path: "\#(tmpPath.string)")"#)
	}
	
	@Test
	func testCanProvideLocalPathWithHyphenAndDotsAndSpacesOhMy() throws {
		let tmpPath = FilePath("/tmp/fake/with-hyphen.two.one-zero/last one")
		/* Original test created the directory, because it must have checked the dependency actually exists, but we do not (and IMHO should not). */
		//try fileManager.createDirectory(at: URL(filePath: tmpPath.string, directoryHint: .isDirectory), withIntermediateDirectories: true)
		let parsed = try #require(ImportSpecification(line: "import Foo  // /tmp/fake/with-hyphen.two.one-zero/last one", scriptFolder: tmpPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "Foo")
		#expect(parsed.moduleSource == .local(tmpPath, scriptFolder: tmpPath))
		#expect(parsed.packageDependencyLine(useSSHForGithubDependencies: false) == #".package(path: "\#(tmpPath.string)")"#)
	}
	
	@Test
	func testCanProvideLocalPathWithSpaces() throws {
		let tmpPath = FilePath("/tmp/fake/with space/last")
		/* Original test created the directory, because it must have checked the dependency actually exists, but we do not (and IMHO should not). */
		//try fileManager.createDirectory(at: URL(filePath: tmpPath.string, directoryHint: .isDirectory), withIntermediateDirectories: true)
		let parsed = try #require(ImportSpecification(line: "import Bar  // /tmp/fake/with space/last", scriptFolder: tmpPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "Bar")
		#expect(parsed.moduleSource == .local(tmpPath, scriptFolder: tmpPath))
		#expect(parsed.packageDependencyLine(useSSHForGithubDependencies: false) == #".package(path: "\#(tmpPath.string)")"#)
	}
	
	@Test
	func testCanProvideLocalPathWithSpacesInLast() throws {
		let tmpPath = FilePath("/tmp/fake/with space/last one")
		/* Original test created the directory, because it must have checked the dependency actually exists, but we do not (and IMHO should not). */
		//try fileManager.createDirectory(at: URL(filePath: tmpPath.string, directoryHint: .isDirectory), withIntermediateDirectories: true)
		let parsed = try #require(ImportSpecification(line: "import Foo  // /tmp/fake/with space/last one", scriptFolder: tmpPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "Foo")
		#expect(parsed.moduleSource == .local(tmpPath, scriptFolder: tmpPath))
		#expect(parsed.packageDependencyLine(useSSHForGithubDependencies: false) == #".package(path: "\#(tmpPath.string)")"#)
	}
	
	@Test
	func testCanProvideLocalPathWithSpacesAndRelativeParentsUp() throws {
		/* Note:
		 * I don’t really understand what this test tests.
		 * It seems more a test for Path (that we do not use anymore) rather than swift-sh (the path was lexically normalized w/o being explicitly told). */
		let tmpPath = FilePath("/tmp/fake/fakechild/../with space/last")
		/* Original test created the directory, because it must have checked the dependency actually exists, but we do not (and IMHO should not). */
		//try fileManager.createDirectory(at: URL(filePath: tmpPath.string, directoryHint: .isDirectory), withIntermediateDirectories: true)
		let parsed = try #require(ImportSpecification(line: "import Bar  // /tmp/fake/with space/last", scriptFolder: tmpPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "Bar")
		#expect(parsed.moduleSource == .local(tmpPath.lexicallyNormalized(), scriptFolder: tmpPath))
		#expect(parsed.packageDependencyLine(useSSHForGithubDependencies: false) == #".package(path: "\#(tmpPath.lexicallyNormalized().string)")"#)
	}
	
	@Test
	func testCanProvideLocalPathWithSpacesAndRelativeParentsUpTwo() throws {
		/* Same note as previous test. */
		let tmpPath = FilePath("/tmp/fake/fakechild1/fakechild2/../../with space/last")
		/* Original test created the directory, because it must have checked the dependency actually exists, but we do not (and IMHO should not). */
		//try fileManager.createDirectory(at: URL(filePath: tmpPath.string, directoryHint: .isDirectory), withIntermediateDirectories: true)
		let parsed = try #require(ImportSpecification(line: "import Bar  // /tmp/fake/with space/last", scriptFolder: tmpPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "Bar")
		#expect(parsed.moduleSource == .local(tmpPath.lexicallyNormalized(), scriptFolder: tmpPath))
		#expect(parsed.packageDependencyLine(useSSHForGithubDependencies: false) == #".package(path: "\#(tmpPath.lexicallyNormalized().string)")"#)
	}
	
	@Test
	func testCanProvideFullURL() throws {
		let parsed = try #require(ImportSpecification(line: "import Foo  // https://example.com/mxcl/Bar.git ~> 1.0", scriptFolder: cwdPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "Foo")
		#expect(parsed.moduleSource == .url(URL(string: "https://example.com/mxcl/Bar.git")!))
		#expect(parsed.constraint == .upToNextMajor(from: .one))
	}
	
	@Test
	func testCanProvideFullURLWithHyphen() throws {
		let parsed = try #require(ImportSpecification(line: "import Bar  // https://example.com/mxcl/swift-bar.git ~> 1.0", scriptFolder: cwdPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "Bar")
		#expect(parsed.moduleSource == .url(URL(string: "https://example.com/mxcl/swift-bar.git")!))
		#expect(parsed.constraint == .upToNextMajor(from: .one))
	}
	
	@Test
	func testCanProvideFullSSHURLWithHyphen() throws {
		let urlStr = "ssh://git@github.com/MariusCiocanel/swift-sh.git"
		let parsed = try #require(ImportSpecification(line: "import Bar  // \(urlStr) ~> 1.0", scriptFolder: cwdPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "Bar")
		#expect(parsed.moduleSource == .url(URL(string: "ssh://git@github.com/MariusCiocanel/swift-sh.git")!))
		#expect(parsed.constraint == .upToNextMajor(from: .one))
	}
	
	@Test
	func testCanProvideCommonSSHURLStyle() throws {
		let uri = "git@github.com:MariusCiocanel/Path.swift.git"
		let parsed = try #require(ImportSpecification(line: "import Path  // \(uri) ~> 1.0", scriptFolder: cwdPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "Path")
		#expect(parsed.moduleSource == .scp(uri))
		#expect(parsed.constraint == .upToNextMajor(from: .one))
	}
	
	@Test
	func testCanProvideCommonSSHURLStyleWithHyphen() throws {
		let uriStr = "git@github.com:MariusCiocanel/swift-sh.git"
		let parsed = try #require(ImportSpecification(line: "import Bar  // \(uriStr) ~> 1.0", scriptFolder: cwdPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "Bar")
		#expect(parsed.moduleSource == .scp("git@github.com:MariusCiocanel/swift-sh.git"))
		#expect(parsed.constraint == .upToNextMajor(from: .one))
	}
	
	@Test(arguments: [
		"struct",
		"class",
		"enum",
		"protocol",
		"typealias",
		"func",
		"let",
		"var",
	])
	func testCanDoSpecifiedImports(kind: String) throws {
		let parsed = try #require(ImportSpecification(line: "import \(kind) Foo.bar  // https://example.com/mxcl/Bar.git ~> 1.0", scriptFolder: cwdPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "Foo")
		#expect(parsed.moduleSource == .url(URL(string: "https://example.com/mxcl/Bar.git")!))
		#expect(parsed.constraint == .upToNextMajor(from: .one))
	}
	
	@Test
	func testCanUseTestable() throws {
		let parsed = try #require(ImportSpecification(line: "@testable import Foo  // @bar ~> 1.0", scriptFolder: cwdPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "Foo")
		#expect(parsed.moduleSource == .github(user: "bar", repo: nil))
		#expect(parsed.constraint == .upToNextMajor(from: .one))
	}
	
	@Test
	func testLatestVersion() throws {
		let parsed = try #require(ImportSpecification(line: "import Foo  // @bar", scriptFolder: cwdPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "Foo")
		#expect(parsed.moduleSource == .github(user: "bar", repo: nil))
		#expect(parsed.constraint == .latest)
	}
	
	@Test
	func testUnversionedHelpersImport() throws {
		let parsed = try #require(ImportSpecification(line: "import SwiftSH_Helpers", scriptFolder: cwdPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "SwiftSH_Helpers")
		#expect(parsed.moduleSource == .github(user: "xcode-actions", repo: "swift-sh"))
		#expect(parsed.constraint == Version(SwiftSH.configuration.version).map{ .exact($0) } ?? .latest)
	}
	
	@Test
	func testVersionedHelpersImport() throws {
		let parsed = try #require(ImportSpecification(line: "import SwiftSH_Helpers // @xcode-actions/swift-sh ~> 3.0", scriptFolder: cwdPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "SwiftSH_Helpers")
		#expect(parsed.moduleSource == .github(user: "xcode-actions", repo: "swift-sh"))
		#expect(parsed.constraint == .upToNextMajor(from: .init(3, 0, 0)))
	}
	
	@Test
	func testVersionedHelpersImportNoRepo() throws {
		let parsed = try #require(ImportSpecification(line: "import SwiftSH_Helpers // ~> 3.0", scriptFolder: cwdPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "SwiftSH_Helpers")
		#expect(parsed.moduleSource == .github(user: "xcode-actions", repo: "swift-sh"))
		#expect(parsed.constraint == .upToNextMajor(from: .init(3, 0, 0)))
	}
	
	@Test
	func testExactVersionedHelpersImportNoRepo() throws {
		let parsed = try #require(ImportSpecification(line: "import SwiftSH_Helpers // == 3.0  ", scriptFolder: cwdPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "SwiftSH_Helpers")
		#expect(parsed.moduleSource == .github(user: "xcode-actions", repo: "swift-sh"))
		#expect(parsed.constraint == .exact(.init(3, 0, 0)))
	}
	
	@Test
	func testExactVersionedHelpersStarCommentImportNoRepo() throws {
		let parsed = try #require(ImportSpecification(line: "import SwiftSH_Helpers /*  ==  3.1.21  */ ", scriptFolder: cwdPath, fileManager: fileManager, logger: logger))
		#expect(parsed.moduleName == "SwiftSH_Helpers")
		#expect(parsed.moduleSource == .github(user: "xcode-actions", repo: "swift-sh"))
		#expect(parsed.constraint == .exact(.init(3, 1, 21)))
	}
	
}
