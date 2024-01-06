// swift-tools-version:5.5
import PackageDescription



let package = Package(
	name: "swift-sh",
	platforms: [
		.macOS(.v10_12)
	],
	products: { var ret: [Product] = [
		.executable(name: "swift-sh", targets: ["swift-sh"]),
		.library(name: "Script", targets: ["Script"]),
		.library(name: "Utility", targets: ["Utility"]),
		.library(name: "Command", targets: ["Command"])]
#if os(macOS)
		ret.append(.executable(name: "swift-sh-edit", targets: ["swift-sh-edit"]))
#endif
		return ret
	}(),
	dependencies: { var ret: [Package.Dependency] = [
		.package(url: "https://github.com/mxcl/Path.swift", from: "1.0.1"),
		.package(url: "https://github.com/mxcl/StreamReader", from: "1.0.0"),
		.package(url: "https://github.com/mxcl/LegibleError", from: "1.0.0"),
		.package(url: "https://github.com/mxcl/Version", from: "2.0.0"),
		.package(url: "https://github.com/krzyzanowskim/CryptoSwift", "1.3.0"..<"1.4.0")]
#if os(macOS)
		ret.append(.package(url: "https://github.com/tuist/xcodeproj", from: "7.0.0"))
#endif
		return ret
	}(),
	targets: { var ret: [Target] = [
		.executableTarget(name: "swift-sh", dependencies: [
			.product(name: "LegibleError", package: "LegibleError"),
			.target(name: "Command"),
		]),
		.target(name: "Script", dependencies: [
			.product(name: "StreamReader", package: "StreamReader"),
			.target(name: "Utility"),
		]),
		.target(name: "Utility", dependencies: [
			.product(name: "Path", package: "Path.swift"),
			.product(name: "Version", package: "Version"),
			.product(name: "CryptoSwift", package: "CryptoSwift"),
		]),
		.target(name: "Command", dependencies: [
			.target(name: "Script")
		]),
		.testTarget(name: "All", dependencies: [
			.target(name: "swift-sh")
		])]
#if os(macOS)
		ret.append(.executableTarget(name: "swift-sh-edit", dependencies: [
			.product(name: "XcodeProj", package: "xcodeproj"),
			.target(name: "Utility"),
		]))
#endif
		return ret
	}()
)
