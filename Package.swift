//swift-tools-version:5.7
import PackageDescription


/* ⚠️ Do not use the concurrency check flags in a release! */
let          noSwiftSettings: [SwiftSetting] = []
//let concurrencySwiftSettings: [SwiftSetting] = [.unsafeFlags(["-Xfrontend", "-warn-concurrency", "-Xfrontend", "-enable-actor-data-race-checks"])]

let package = Package(
	name: "swift-sh",
	platforms: [
		.macOS(.v13)
	],
	products: { let ret: [Product] = [
		.executable(name: "swift-sh", targets: ["swift-sh"])]
		return ret
	}(),
	dependencies: { let ret: [Package.Dependency] = [
		.package(url: "https://github.com/apple/swift-crypto.git",                     "1.0.0" ..< "4.0.0"),
		.package(url: "https://github.com/apple/swift-argument-parser.git",            from: "1.2.0"),
		.package(url: "https://github.com/Frizlab/UnwrapOrThrow.git",                  from: "1.0.1"),
		.package(url: "https://github.com/Frizlab/swift-xdg.git",                      from: "1.0.0"),
		.package(url: "https://github.com/mxcl/LegibleError.git",                      from: "1.0.0"),
		.package(url: "https://github.com/mxcl/Version.git",                           from: "2.0.0"),
		.package(url: "https://github.com/xcode-actions/clt-logger.git",               from: "0.8.0"),
		.package(url: "https://github.com/xcode-actions/stream-reader.git",            from: "3.5.0"),
		.package(url: "https://github.com/xcode-actions/swift-process-invocation.git", from: "1.0.0")]
		return ret
	}(),
	targets: { let ret: [Target] = [
		.executableTarget(name: "swift-sh", dependencies: [
			.product(name: "ArgumentParser",    package: "swift-argument-parser"),
			.product(name: "CLTLogger",         package: "clt-logger"),
			.product(name: "Crypto",            package: "swift-crypto"),
			.product(name: "LegibleError",      package: "LegibleError"),
			.product(name: "ProcessInvocation", package: "swift-process-invocation"),
			.product(name: "StreamReader",      package: "stream-reader"),
			.product(name: "UnwrapOrThrow",     package: "UnwrapOrThrow"),
			.product(name: "Version",           package: "Version"),
			.product(name: "XDG",               package: "swift-xdg"),
		], exclude: ["Legacy"], swiftSettings: noSwiftSettings),
		.target(name: "SwiftSH_Helpers", dependencies: [
			.product(name: "ArgumentParser",    package: "swift-argument-parser"),
			.product(name: "CLTLogger",         package: "clt-logger"),
			.product(name: "ProcessInvocation", package: "swift-process-invocation"),
			.product(name: "StreamReader",      package: "stream-reader"),
			.product(name: "XDG",               package: "swift-xdg"),
		], swiftSettings: noSwiftSettings),
		.testTarget(name: "swift-shTests", dependencies: [
			.target(name: "swift-sh")
		], path: "Tests", exclude: ["Legacy"], swiftSettings: noSwiftSettings)]
		return ret
	}()
)
