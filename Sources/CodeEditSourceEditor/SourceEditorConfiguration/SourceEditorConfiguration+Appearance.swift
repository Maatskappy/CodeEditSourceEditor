//
//  SourceEditorConfiguration+Appearance.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 6/16/25.
//

import AppKit

extension SourceEditorConfiguration {
    /// Configure the appearance of the editor. Font, theme, line height, etc.
    public struct Appearance: Equatable {
        /// The theme for syntax highlighting.
        public var theme: EditorTheme

        /// Determines whether the editor uses the theme's background color, or a transparent background color.
        public var useThemeBackground: Bool = true

        /// The default font.
        public var font: NSFont

        /// The line height multiplier (e.g. `1.2`).
        public var lineHeightMultiple: Double

        /// The amount of space to use between letters, as a percent. Eg: `1.0` = no space, `1.5` = 1/2 a
        /// character's width between characters, etc. Defaults to `1.0`.
        public var letterSpacing: Double = 1.0

        /// Whether lines wrap to the width of the editor.
        public var wrapLines: Bool

        /// If true, uses the system cursor on `>=macOS 14`.
        public var useSystemCursor: Bool = true

        /// The visual tab width in number of spaces.
        public var tabWidth: Int

        /// The type of highlight to use to highlight bracket pairs.
        /// See ``BracketPairEmphasis`` for more information. Defaults to `.flash`.
        public var bracketPairEmphasis: BracketPairEmphasis? = .flash

        /// The font for gutter line numbers. `nil` derives a ruler font from ``font``.
        public var gutterFont: NSFont?

        /// The colour of gutter line numbers. `nil` uses the theme's text colour at 35% opacity.
        public var gutterTextColor: NSColor?

        /// The colour of the line number on lines containing a cursor. `nil` uses the theme's text colour when the
        /// editor is editable, and ``gutterTextColor`` (no emphasis) when it is read-only.
        public var gutterSelectedLineTextColor: NSColor?

        /// Whether the gutter fills the background of lines containing a cursor. When `false`, no fill is drawn but the
        /// line number still uses ``gutterSelectedLineTextColor``. The fill is never drawn in a read-only editor.
        public var gutterHighlightsSelectedLineBackground: Bool = true

        /// The minimum number of digits the gutter reserves width for, so the column doesn't widen as the line count
        /// crosses 99, 999, etc. `nil` reserves 3 digits.
        public var gutterMinimumDigits: Int?

        /// Create a new appearance configuration object.
        /// - Parameters:
        ///   - theme: The theme for syntax highlighting.
        ///   - useThemeBackground: Determines whether the editor uses the theme's background color, or a transparent
        ///                         background color.
        ///   - font: The default font.
        ///   - lineHeightMultiple: The line height multiplier (e.g. `1.2`).
        ///   - letterSpacing: The amount of space to use between letters, as a percent. Eg: `1.0` = no space, `1.5`
        ///                    = 1/2 of a character's width between characters, etc. Defaults to `1.0`.
        ///   - wrapLines: Whether lines wrap to the width of the editor.
        ///   - useSystemCursor: If true, uses the system cursor on `>=macOS 14`.
        ///   - tabWidth: The visual tab width in number of spaces.
        ///   - bracketPairEmphasis: The type of highlight to use to highlight bracket pairs. See
        ///                          ``BracketPairEmphasis`` for more information. Defaults to `.flash`.
        ///   - gutterFont: The font for gutter line numbers. `nil` derives a ruler font from `font`.
        ///   - gutterTextColor: The colour of gutter line numbers. `nil` uses the theme's text colour at 35% opacity.
        ///   - gutterSelectedLineTextColor: The colour of the line number on lines containing a cursor. `nil` uses the
        ///                                  theme's text colour when editable, no emphasis when read-only.
        ///   - gutterHighlightsSelectedLineBackground: Whether the gutter fills the background of lines containing a
        ///                                             cursor. Defaults to `true`.
        ///   - gutterMinimumDigits: The minimum number of digits the gutter reserves width for. `nil` reserves 3.
        public init(
            theme: EditorTheme,
            useThemeBackground: Bool = true,
            font: NSFont,
            lineHeightMultiple: Double = 1.2,
            letterSpacing: Double = 1.0,
            wrapLines: Bool,
            useSystemCursor: Bool = true,
            tabWidth: Int = 4,
            bracketPairEmphasis: BracketPairEmphasis? = .flash,
            gutterFont: NSFont? = nil,
            gutterTextColor: NSColor? = nil,
            gutterSelectedLineTextColor: NSColor? = nil,
            gutterHighlightsSelectedLineBackground: Bool = true,
            gutterMinimumDigits: Int? = nil
        ) {
            self.theme = theme
            self.useThemeBackground = useThemeBackground
            self.font = font
            self.lineHeightMultiple = lineHeightMultiple
            self.letterSpacing = letterSpacing
            self.wrapLines = wrapLines
            if #available(macOS 14, *) {
                self.useSystemCursor = useSystemCursor
            } else {
                self.useSystemCursor = false
            }
            self.tabWidth = tabWidth
            self.bracketPairEmphasis = bracketPairEmphasis
            self.gutterFont = gutterFont
            self.gutterTextColor = gutterTextColor
            self.gutterSelectedLineTextColor = gutterSelectedLineTextColor
            self.gutterHighlightsSelectedLineBackground = gutterHighlightsSelectedLineBackground
            self.gutterMinimumDigits = gutterMinimumDigits
        }

        @MainActor
        func didSetOnController(controller: TextViewController, oldConfig: Appearance?) {
            var needsHighlighterInvalidation = false

            if oldConfig?.font != font {
                controller.textView.font = font
                controller.textView.typingAttributes = controller.attributesFor(nil)
                needsHighlighterInvalidation = true
            }

            if oldConfig?.theme != theme || oldConfig?.useThemeBackground != useThemeBackground {
                updateControllerNewTheme(controller: controller)
                needsHighlighterInvalidation = true
            }

            updateGutterIfNeeded(controller: controller, oldConfig: oldConfig)

            if oldConfig?.tabWidth != tabWidth {
                controller.paragraphStyle = controller.generateParagraphStyle()
                controller.textView.layoutManager.setNeedsLayout()
                needsHighlighterInvalidation = true
            }

            if oldConfig?.lineHeightMultiple != lineHeightMultiple {
                controller.textView.layoutManager.lineHeightMultiplier = lineHeightMultiple
            }

            if oldConfig?.wrapLines != wrapLines {
                controller.textView.layoutManager.wrapLines = wrapLines
                controller.minimapView.layoutManager?.wrapLines = wrapLines
                controller.scrollView.hasHorizontalScroller = !wrapLines
                controller.updateTextInsets()
            }

            // useThemeBackground isn't needed

            if oldConfig?.letterSpacing != letterSpacing {
                controller.textView.letterSpacing = letterSpacing
                needsHighlighterInvalidation = true
            }

            if oldConfig?.bracketPairEmphasis != bracketPairEmphasis {
                controller.emphasizeSelectionPairs()
            }

            // Cant put these in one if sadly
            if #available(macOS 14, *) {
                if oldConfig?.useSystemCursor != useSystemCursor {
                    controller.textView.useSystemCursor = useSystemCursor
                }
            }

            if needsHighlighterInvalidation {
                controller.highlighter?.invalidate()
            }
        }

        /// Restyles the gutter when anything it draws with differs from `oldConfig` (always on first setup).
        @MainActor
        private func updateGutterIfNeeded(controller: TextViewController, oldConfig: Appearance?) {
            guard let oldConfig else {
                controller.styleGutterView()
                return
            }
            let changed = oldConfig.font != font
                || oldConfig.theme != theme
                || oldConfig.useThemeBackground != useThemeBackground
                || oldConfig.gutterFont != gutterFont
                || oldConfig.gutterTextColor != gutterTextColor
                || oldConfig.gutterSelectedLineTextColor != gutterSelectedLineTextColor
                || oldConfig.gutterHighlightsSelectedLineBackground != gutterHighlightsSelectedLineBackground
                || oldConfig.gutterMinimumDigits != gutterMinimumDigits
            if changed {
                controller.styleGutterView()
            }
        }

        private func updateControllerNewTheme(controller: TextViewController) {
            controller.textView.layoutManager.setNeedsLayout()
            controller.textView.textStorage.setAttributes(
                controller.attributesFor(nil),
                range: NSRange(location: 0, length: controller.textView.textStorage.length)
            )
            controller.textView.selectionManager.selectionBackgroundColor = theme.selection
            controller.textView.selectionManager.selectedLineBackgroundColor = getThemeBackground(
                systemAppearance: controller.systemAppearance
            )
            controller.textView.selectionManager.insertionPointColor = theme.insertionPoint
            controller.textView.enclosingScrollView?.backgroundColor = if useThemeBackground {
                theme.background
            } else {
                .clear
            }

            controller.minimapView.setTheme(theme)
            controller.reformattingGuideView?.theme = theme
            controller.textView.typingAttributes = controller.attributesFor(nil)
        }

        /// Finds the preferred use theme background.
        /// - Returns: The background color to use.
        private func getThemeBackground(systemAppearance: NSAppearance.Name?) -> NSColor {
            if useThemeBackground {
                return theme.lineHighlight
            }

            if systemAppearance == .darkAqua {
                return NSColor.quaternaryLabelColor
            }

            return NSColor.selectedTextBackgroundColor.withSystemEffect(.disabled)
        }
    }
}
