import Foundation



extension String {
	
	/* From TextOutputStream documentation. */
	func escaped() -> String {
		return unicodeScalars.lazy.map{ scalar in
			scalar.escaped(asASCII: true)
		}.joined(separator: "")
	}
	
}
