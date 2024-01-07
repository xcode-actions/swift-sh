import Foundation

import ArgumentParser
import CLTLogger
import Logging



final class GlobalOptions : ParsableArguments {
	
	@Flag(name: .shortAndLong)
	var verbose: Bool = false
	
	private(set) lazy var logger: Logger = {
		/* Bootstrap the logging system first. */
//		switch logHandler ?? conf?.logHandler ?? .cltLogger {
//			case .jsonLogger:
//				LoggingSystem.bootstrap({ label, metadataProvider in
//					var ret = JSONLogger(label: label, fd: !logToStdout ? .standardError : .standardOutput, metadataProvider: metadataProvider)
//					ret.logLevel = resolvedLogLevel
//					return ret
//				}, metadataProvider: nil)
//				
//			case .cltLogger:
				LoggingSystem.bootstrap({ _, metadataProvider in
					var ret = CLTLogger(multilineMode: .allMultiline, metadataProvider: metadataProvider)
//					ret.metadata = ["zz-label": "\(label)"] /* Note: CLTLogger does not use the label by default so we add it in the metadata. */
					return ret
				}, metadataProvider: nil /* .init{ ["zz-date": "\(Date())"] } */ )
//		}
		/* Then create and return the logger. */
		var logger = Logger(label: "com.xcode-actions.swift-sh")
		logger.logLevel = verbose ? .debug : .notice
		return logger
	}()
	
}
