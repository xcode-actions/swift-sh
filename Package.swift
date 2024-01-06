// swift-tools-version:5.5
import PackageDescription


let package = Package(
	name: "swift-sh",
	platforms: [
		.macOS(.v11)
	],
	products: { var ret: [Product] = [
		.executable(name: "swift-sh", targets: ["swift-sh"])]
		return ret
	}(),
	dependencies: { var ret: [Package.Dependency] = [
		.package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
//		.package(url: "https://github.com/mxcl/Path.swift", from: "1.0.1"),
//		.package(url: "https://github.com/mxcl/StreamReader", from: "1.0.0"),
		.package(url: "https://github.com/mxcl/LegibleError", from: "1.0.0"),
//		.package(url: "https://github.com/mxcl/Version", from: "2.0.0"),
//		.package(url: "https://github.com/krzyzanowskim/CryptoSwift", "1.3.0"..<"1.4.0"),
		.package(url: "https://github.com/xcode-actions/clt-logger.git", from: "0.8.0")]
		return ret
	}(),
	targets: { var ret: [Target] = [
		.executableTarget(name: "swift-sh", dependencies: [
			.product(name: "ArgumentParser", package: "swift-argument-parser"),
			.product(name: "CLTLogger",      package: "clt-logger"),
			.product(name: "LegibleError",   package: "LegibleError")
		], path: "Sources", exclude: ["Legacy"]),
		.testTarget(name: "swift-shTests", dependencies: [
			.target(name: "swift-sh")
		], path: "Tests", exclude: ["Legacy"])]
		return ret
	}()
)
