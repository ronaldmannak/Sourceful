//
//  InnerTextView.swift
//  SavannaKit
//
//  Created by Louis D'hauwe on 09/07/2017.
//  Copyright © 2017 Silver Fox. All rights reserved.
//

import Foundation
import CoreGraphics

#if os(macOS)
	import AppKit
    import Carbon.HIToolbox
#else
	import UIKit
#endif

protocol InnerTextViewDelegate: class {
	func didUpdateCursorFloatingState()
}

class InnerTextView: TextView {
	
	weak var innerDelegate: InnerTextViewDelegate?
	
	var theme: SyntaxColorTheme?
	
	var cachedParagraphs: [Paragraph]?
    
    var autocompleteWords: [String]?
	
	func invalidateCachedParagraphs() {
		cachedParagraphs = nil
	}
	
	func hideGutter() {
		gutterWidth = theme?.gutterStyle.minimumWidth ?? 0.0
	}
	
	func updateGutterWidth(for numberOfCharacters: Int) {
		
		let leftInset: CGFloat = 4.0
		let rightInset: CGFloat = 4.0
		
		let charWidth: CGFloat = 10.0
		
		gutterWidth = max(theme?.gutterStyle.minimumWidth ?? 0.0, CGFloat(numberOfCharacters) * charWidth + leftInset + rightInset)
		
	}
	
	#if os(iOS)
	
	var isCursorFloating = false
	
	override func beginFloatingCursor(at point: CGPoint) {
		super.beginFloatingCursor(at: point)
		
		isCursorFloating = true
		innerDelegate?.didUpdateCursorFloatingState()

	}
	
	override func endFloatingCursor() {
		super.endFloatingCursor()
		
		isCursorFloating = false
		innerDelegate?.didUpdateCursorFloatingState()

	}
	
	override public func draw(_ rect: CGRect) {
		
		guard let theme = theme else {
			super.draw(rect)
			hideGutter()
			return
		}
		
		let textView = self

		if theme.lineNumbersStyle == nil  {

			hideGutter()

			let gutterRect = CGRect(x: 0, y: rect.minY, width: textView.gutterWidth, height: rect.height)
			let path = BezierPath(rect: gutterRect)
			path.fill()
			
		} else {
			
			let components = textView.text.components(separatedBy: .newlines)
			
			let count = components.count
			
			let maxNumberOfDigits = "\(count)".count
			
			textView.updateGutterWidth(for: maxNumberOfDigits)
            
            var paragraphs: [Paragraph]
            
            if let cached = textView.cachedParagraphs {
                
                paragraphs = cached
                
            } else {
                
                paragraphs = generateParagraphs(for: textView, flipRects: false)
                textView.cachedParagraphs = paragraphs
                
            }
			
			theme.gutterStyle.backgroundColor.setFill()
			
			let gutterRect = CGRect(x: 0, y: rect.minY, width: textView.gutterWidth, height: rect.height)
			let path = BezierPath(rect: gutterRect)
			path.fill()
			
			drawLineNumbers(paragraphs, in: rect, for: self)
			
		}
		

		super.draw(rect)

	}
	#endif
	
	var gutterWidth: CGFloat {
		set {
			
			#if os(macOS)
				textContainerInset = NSSize(width: newValue, height: 0)
			#else
				textContainerInset = UIEdgeInsets(top: 0, left: newValue, bottom: 0, right: 0)
			#endif
			
		}
		get {
			
			#if os(macOS)
				return textContainerInset.width
			#else
				return textContainerInset.left
			#endif
			
		}
	}
//	var gutterWidth: CGFloat = 0.0 {
//		didSet {
//
//			textContainer.exclusionPaths = [UIBezierPath(rect: CGRect(x: 0.0, y: 0.0, width: gutterWidth, height: .greatestFiniteMagnitude))]
//
//		}
//
//	}
	
	#if os(iOS)
	
	override func caretRect(for position: UITextPosition) -> CGRect {
		
		var superRect = super.caretRect(for: position)
		
		guard let theme = theme else {
			return superRect
		}
		
		let font = theme.font
		
		// "descender" is expressed as a negative value,
		// so to add its height you must subtract its value
		superRect.size.height = font.pointSize - font.descender
		
		return superRect
	}
	
	#endif
    
    #if os(macOS)
    
//    open override var canBecomeKeyView: Bool {
//        return true
//    }
//
//    open override var acceptsFirstResponder: Bool {
//        return true
//    }
    
    override func didChangeText() {
        
        super.didChangeText()
        
        if let event = self.window?.currentEvent,
            event.type == .keyDown,
              (event.keyCode == UInt16(kVK_Escape) || event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_UpArrow) || event.keyCode == UInt16(kVK_DownArrow) || event.keyCode == UInt16(kVK_LeftArrow) || event.keyCode == UInt16(kVK_RightArrow)) {
            
            NSObject.cancelPreviousPerformRequests(withTarget: self)
            return
        }
        
        // Invoke lint after delay
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        perform(#selector(complete(_:)), with: nil, afterDelay: 0.7)
    }
	
    override func completions(forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
        
        guard charRange.length > 0, let range = Range(charRange, in: text) else { return nil }

        var wordList = [String]()
        let partialWord = String(text[range])

        // Add words in the document
        let documentWords: [String] = {
            // do nothing if the particle word is a symbol
            guard charRange.length > 1 || CharacterSet.alphanumerics.contains(partialWord.unicodeScalars.first!) else { return [] }

            let pattern = "(?:^|\\b|(?<=\\W))" + NSRegularExpression.escapedPattern(for: partialWord) + "\\w+?(?:$|\\b)"
            let regex = try! NSRegularExpression(pattern: pattern)

            return regex.matches(in: self.string, range: NSRange(..<self.string.endIndex, in: self.string)).map { (self.string as NSString).substring(with: $0.range) }
        }()
        wordList.append(contentsOf: documentWords)

        // Add words defined in lexer
        if let autocompleteWords = self.autocompleteWords {
           
             let syntaxWords = autocompleteWords.filter { $0.range(of: partialWord, options: [.caseInsensitive, .anchored]) != nil }

            wordList.append(contentsOf: syntaxWords)
        }
                
        // Remove double words
        let set:Set<String> = Set(wordList)

        return Array(set)
    }
    
    override func changeFont(_ sender: Any?) {
        guard let oldFont = self.font, let fontManager = sender as? NSFontManager else { return }
        let newFont = fontManager.convert(oldFont)
        self.font = newFont

        // FIXME: line number view font size stays old font size.
        // Line numbers are drawn in TextViewWrapperView's draw
        // and uses font attributes of paragraph.
        // Line numbers currenlty are only redrawn when a new line is added
    }
    
    #endif
}
