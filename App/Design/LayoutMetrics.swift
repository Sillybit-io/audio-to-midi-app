import CoreGraphics

/// Sizes the views need that the generated token set doesn't name. Each is built from those tokens, so the 4-pt grid
/// stays the one source of sizes. `DesignTokens.swift` is generated from the prototype and isn't edited by hand.
extension Metric {
    /// The narrowest window. The handoff's 960 pt leaves the detail column about 430 pt with both side panes open, too
    /// little for the MIDI editor's transport, tools, undo, Save, Export and inspector button on one toolbar.
    static let windowMinWide = windowMinW + sp10 * 3
    /// The Original ↔ Notes mix slider (220 pt in the handoff).
    static let mixSliderW = sheetW / 2
    /// Speed and zoom sliders, and the download progress bar in Settings.
    static let sliderW = sp10 + sp9
    /// Numeric fields: slice times, note start, length and velocity.
    static let fieldW = sp10 + sp9
    /// The widest the MIDI file chip in the footer grows before its name is shortened.
    static let dragChipW = sp10 * 5
    /// The `1.00×` speed readout and the progress percentage.
    static let readoutW = sp10 - sp4
    /// The licence text box in the licence sheet.
    static let licenceTextH = sidebarW - sp10
    /// The licence sheet.
    static let licenceSheetW = settingsW - sp9 - sp10
    /// The About window and the Keyboard Shortcuts sheet.
    static let aboutH = sheetW + sp7
    /// The shortest Settings window.
    static let settingsMinH = sheetW + sp10 + sp9
    /// The large symbol on the drop zone.
    static let dropSymbol = sp10
    /// The playhead and a selected note's outline.
    static let strongLine = ringW / 2
    /// A velocity bar, and the dot on a selected one.
    static let velBarW = ringW
    static let velDot = sp3
    /// How far a pointer moves before a click becomes a drag.
    static let dragSlop = ringW
    /// The shortest velocity bar, so a note with velocity 1 is still visible.
    static let velBarMinH = sp1
    /// How close to a velocity bar a paint stroke has to pass.
    static let velReach = sp2 + sp1 / 2
    /// Piano-roll zoom limits and the editor's starting zoom. These are speeds in points per second, not layout sizes.
    static let ppsMin: CGFloat = 10
    static let ppsEditorMin: CGFloat = 30
    static let ppsMax: CGFloat = 400
    static let ppsEditor: CGFloat = 120
}
