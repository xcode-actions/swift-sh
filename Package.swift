//swift-tools-version:5.7
import PackageDescription


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
		.package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
		.package(url: "https://github.com/Frizlab/UnwrapOrThrow.git",       from: "1.0.1-rc"),
		.package(url: "https://github.com/Frizlab/swift-xdg.git",           from: "1.0.0-beta"),
		.package(url: "https://github.com/mxcl/LegibleError.git",           from: "1.0.0"),
		.package(url: "https://github.com/mxcl/Version.git",                from: "2.0.0"),
		.package(url: "https://github.com/xcode-actions/clt-logger.git",    from: "0.8.0"),
		.package(url: "https://github.com/xcode-actions/stream-reader.git", from: "3.5.0"),
		.package(url: "https://github.com/xcode-actions/XcodeTools.git",    revision: "0.10.0")]
		return ret
	}(),
	targets: { let ret: [Target] = [
		.executableTarget(name: "swift-sh", dependencies: [
			.product(name: "ArgumentParser", package: "swift-argument-parser"),
			.product(name: "CLTLogger",      package: "clt-logger"),
			.product(name: "LegibleError",   package: "LegibleError"),
			.product(name: "StreamReader",   package: "stream-reader"),
			.product(name: "UnwrapOrThrow",  package: "UnwrapOrThrow"),
			.product(name: "Version",        package: "Version"),
			.product(name: "XcodeTools",     package: "XcodeTools"),
			.product(name: "XDG",            package: "swift-xdg"),
		], path: "Sources", exclude: ["Legacy"]),
		.testTarget(name: "swift-shTests", dependencies: [
			.target(name: "swift-sh")
		], path: "Tests", exclude: ["Legacy"])]
		return ret
	}()
)
