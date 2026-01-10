//swift-tools-version:6.0
import PackageDescription


let commonSwiftSettings: [SwiftSetting] = []

let package = Package(
	name: "swift-sh",
	platforms: [
		.macOS(.v13)
	],
	products: [
		.executable(name: "swift-sh",        targets: ["swift-sh"]),
		.library   (name: "SwiftSH_Helpers", targets: ["SwiftSH_Helpers"]),
	],
	dependencies: [
		.package(url: "https://github.com/apple/swift-argument-parser.git",            from: "1.2.0"),
		.package(url: "https://github.com/apple/swift-crypto.git",                     "1.0.0" ..< "5.0.0"),
		.package(url: "https://github.com/apple/swift-log.git",                        from: "1.8.0"),
		.package(url: "https://github.com/apple/swift-system.git",                     from: "1.0.0"), /* We’re aware of the existence of System on macOS. After some thinking/research, we decided to agree with <https://forums.swift.org/t/50719/5>. */
		.package(url: "https://github.com/Frizlab/InlineObjectConfig.git",             from: "1.0.0"),
		.package(url: "https://github.com/Frizlab/swift-xdg.git",                      from: "2.0.0"),
		.package(url: "https://github.com/Frizlab/UnwrapOrThrow.git",                  from: "1.1.0"),
		.package(url: "https://github.com/mxcl/LegibleError.git",                      from: "1.0.0"),
		.package(url: "https://github.com/mxcl/Version.git",                           from: "2.0.0"),
		.package(url: "https://github.com/xcode-actions/clt-logger.git",               from: "1.0.0"),
		.package(url: "https://github.com/xcode-actions/stream-reader.git",            from: "3.5.2"),
		.package(url: "https://github.com/xcode-actions/swift-process-invocation.git", from: "1.3.0-beta.5"),
	],
	targets: [
		.executableTarget(name: "swift-sh", dependencies: [
			.product(name: "ArgumentParser",     package: "swift-argument-parser"),
			.product(name: "CLTLogger",          package: "clt-logger"),
			.product(name: "Crypto",             package: "swift-crypto"),
			.product(name: "InlineObjectConfig", package: "InlineObjectConfig"),
			.product(name: "LegibleError",       package: "LegibleError"),
			.product(name: "Logging",            package: "swift-log"),
			.product(name: "ProcessInvocation",  package: "swift-process-invocation"),
			.product(name: "StreamReader",       package: "stream-reader"),
			.product(name: "SystemPackage",      package: "swift-system"),
			.product(name: "UnwrapOrThrow",      package: "UnwrapOrThrow"),
			.product(name: "Version",            package: "Version"),
			.product(name: "XDG",                package: "swift-xdg"),
		], exclude: ["Legacy"], swiftSettings: commonSwiftSettings),
		.target(name: "SwiftSH_Helpers", dependencies: [
			.product(name: "ArgumentParser",     package: "swift-argument-parser"),
			.product(name: "CLTLogger",          package: "clt-logger"),
			.product(name: "InlineObjectConfig", package: "InlineObjectConfig"),
			.product(name: "Logging",            package: "swift-log"),
			.product(name: "ProcessInvocation",  package: "swift-process-invocation"),
			.product(name: "StreamReader",       package: "stream-reader"),
			.product(name: "SystemPackage",      package: "swift-system"),
			.product(name: "UnwrapOrThrow",      package: "UnwrapOrThrow"),
			.product(name: "XDG",                package: "swift-xdg"),
		], swiftSettings: commonSwiftSettings),
		
		/* We do only one target to test swift-sh and its helpers, for simplicity. */
		.testTarget(name: "SwiftSHTests", dependencies: [
			.target(name: "swift-sh"),
			.target(name: "SwiftSH_Helpers"),
			.product(name: "Logging",       package: "swift-log"),
			.product(name: "SystemPackage", package: "swift-system"),
		], path: "Tests", exclude: ["Legacy"], swiftSettings: commonSwiftSettings),
	]
)
