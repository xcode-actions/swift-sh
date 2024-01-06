#!/usr/bin/swift sh
import Foundation

import Ink /* @JohnSundell == 0.5.0 */



let markdown = """
# Ink parses markdown and renders to HTML
## Features
- Header blocks
- List blocks
	- Nested list
- Character styles
	- *Italic*
	- **Bold**
	- ~~Strikethrough~~

## HTML output:

"""
let html = MarkdownParser().html(from: markdown)
print(markdown)
print(html)
