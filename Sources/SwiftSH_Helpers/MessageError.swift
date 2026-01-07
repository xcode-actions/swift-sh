import Foundation



public struct MessageError : Error, CustomStringConvertible {
	
	public var message: String
	
	public init(_ message: String) {
		self.message = message
	}
	
	public var description: String {
		message
	}
	
}
