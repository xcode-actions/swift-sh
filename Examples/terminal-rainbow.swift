#!/usr/bin/env -S swift-sh --
import Foundation

import Chalk /* @mxcl == 0.4.0 */



extension Int {
	
	var fg: UInt8 {
		if !(16..<250 ~= self) || 24...36 ~= (self - 16) % 36 {
			return 16
		} else {
			return 255
		}
	}
	
	var bg: UInt8 {
		return UInt8(self)
	}
	
	var paddedString: String {
		return " \(self)".padding(toLength: 5, withPad: " ", startingAt: 0)
	}
	
	var terminator: String {
		return (self + 3).isMultiple(of: 6) ? "\n" : ""
	}
	
}


for x in 0...255 {
	print("\(x.paddedString, color: .extended(x.fg), background: .extended(x.bg))", terminator: x.terminator)
}
