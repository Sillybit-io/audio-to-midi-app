// DesignTokens.swift — generated from tokens.css by swiftui/generate_tokens.py. Do not hand-edit:
// change tokens.css, then regenerate. Every section below is rebuilt on each run.
// Rule for SwiftUI: prefer the native semantic colour in `Native` whenever one exists — it follows
// the user's accent, Increase Contrast and vibrancy for free. Use `Token` only for app-specific colours
// (instrument palette, piano roll, waveform, playhead, app icon).

import SwiftUI
import AppKit

extension Color {
    /// Light/dark pair resolved by the current NSAppearance.
    init(light: UInt32, lightAlpha: Double = 1, dark: UInt32, darkAlpha: Double = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light, a = isDark ? darkAlpha : lightAlpha
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: CGFloat(a))
        })
    }
}

/// Native macOS colours that the prototype tokens stand in for.
enum Native {
    static let bg = Color(nsColor: .windowBackgroundColor)   // --bg
    static let surface = Color(nsColor: .controlBackgroundColor)   // --surface
    static let fg = Color(nsColor: .labelColor)   // --fg
    static let fgSecondary = Color(nsColor: .secondaryLabelColor)   // --fg-secondary
    static let muted = Color(nsColor: .tertiaryLabelColor)   // --muted
    static let border = Color(nsColor: .separatorColor)   // --border
    static let accent = Color.accentColor   // --accent
    static let success = Color(nsColor: .systemGreen)   // --success
    static let warn = Color(nsColor: .systemOrange)   // --warn
    static let danger = Color(nsColor: .systemRed)   // --danger
}

/// Every colour token from tokens.css, light + dark (sRGB, converted from OKLCH).
enum Token {
    static let desktop = Color(light: 0xA7BACD, dark: 0x202F42)   // --desktop
    static let bg = Color(light: 0xF6F7F8, dark: 0x17181A)   // --bg
    static let surface = Color(light: 0xFFFFFF, dark: 0x0F0F11)   // --surface
    static let surfaceSunken = Color(light: 0xEEEEF0, dark: 0x090A0B)   // --surface-sunken
    static let surfaceRaised = Color(light: 0xFFFFFF, dark: 0x232426)   // --surface-raised
    static let glass = Color(light: 0xF7F8FA, lightAlpha: 0.72, dark: 0x252628, darkAlpha: 0.7)   // --glass
    static let glassStrong = Color(light: 0xFBFCFD, lightAlpha: 0.88, dark: 0x28292B, darkAlpha: 0.88)   // --glass-strong
    static let glassEdge = Color(light: 0xFFFFFF, lightAlpha: 0.7, dark: 0xFFFFFF, darkAlpha: 0.1)   // --glass-edge
    static let scrim = Color(light: 0x13161B, lightAlpha: 0.28, dark: 0x000000, darkAlpha: 0.45)   // --scrim
    static let fg = Color(light: 0x101214, dark: 0xEEEEF0)   // --fg
    static let fgSecondary = Color(light: 0x4B4D50, dark: 0xB6B7BA)   // --fg-secondary
    static let muted = Color(light: 0x67696C, dark: 0x909295)   // --muted
    static let fgOnAccent = Color(light: 0xFFFFFF, dark: 0xFFFFFF)   // --fg-on-accent
    static let border = Color(light: 0xD6D7D9, dark: 0xFFFFFF, darkAlpha: 0.1)   // --border
    static let borderStrong = Color(light: 0xBCBEC0, dark: 0xFFFFFF, darkAlpha: 0.18)   // --border-strong
    static let gridBeat = Color(light: 0xE0E1E3, dark: 0xFFFFFF, darkAlpha: 0.05)   // --grid-beat
    static let gridBar = Color(light: 0xC6C7CA, dark: 0xFFFFFF, darkAlpha: 0.13)   // --grid-bar
    static let accent = Color(light: 0x006CE2, dark: 0x006FDC)   // --accent
    static let accentHover = Color(light: 0x005CD1, dark: 0x005FCB)   // --accent-hover
    static let accentPress = Color(light: 0x004EBB, dark: 0x0054B8)   // --accent-press
    static let accentSoft = Color(light: 0x006CE2, lightAlpha: 0.14, dark: 0x1485F4, darkAlpha: 0.24)   // --accent-soft
    static let accentText = Color(light: 0x005CD1, dark: 0x5CA7FF)   // --accent-text
    static let focusRing = Color(light: 0x006CE2, lightAlpha: 0.85, dark: 0x50A0FF, darkAlpha: 0.85)   // --focus-ring
    static let success = Color(light: 0x007329, dark: 0x3FC168)   // --success
    static let warn = Color(light: 0x9E5300, dark: 0xF0B135)   // --warn
    static let danger = Color(light: 0xD02C2A, dark: 0xF75D59)   // --danger
    static let warnSoft = Color(light: 0xE6B55D, lightAlpha: 0.22, dark: 0xF0B135, darkAlpha: 0.14)   // --warn-soft
    static let instPiano = Color(light: 0x1C7DEE, dark: 0x3B93F7)   // --inst-piano
    static let instGuitar = Color(light: 0xE57600, dark: 0xF48D2F)   // --inst-guitar
    static let instBass = Color(light: 0x8F54DC, dark: 0xA473EE)   // --inst-bass
    static let instStrings = Color(light: 0x00A166, dark: 0x2FC183)   // --inst-strings
    static let instVoice = Color(light: 0xE64887, dark: 0xF7619A)   // --inst-voice
    static let instBrass = Color(light: 0xD6A20A, dark: 0xECBD3A)   // --inst-brass
    static let instWoodwinds = Color(light: 0x059EB1, dark: 0x39B7CB)   // --inst-woodwinds
    static let instSynth = Color(light: 0xD02C2A, dark: 0xF0574E)   // --inst-synth
    static let instDrums = Color(light: 0x886B54, dark: 0xBD9E86)   // --inst-drums
    static let instAll = Color(light: 0x656F81, dark: 0x949FB2)   // --inst-all
    static let noteEdge = Color(light: 0x000000, lightAlpha: 0.18, dark: 0xFFFFFF, darkAlpha: 0.22)   // --note-edge
    static let appIconBgTop = Color(light: 0x212E45, dark: 0x212E45)   // --app-icon-bg-top
    static let appIconBg = Color(light: 0x0C1323, dark: 0x0C1323)   // --app-icon-bg
    static let appIconRim = Color(light: 0xFFFFFF, lightAlpha: 0.14, dark: 0xFFFFFF, darkAlpha: 0.14)   // --app-icon-rim
    static let appIconWave = Color(light: 0xCAD1DF, dark: 0xCAD1DF)   // --app-icon-wave
    static let keyWhite = Color(light: 0xFCFCFC, dark: 0xC9CACC)   // --key-white
    static let keyBlack = Color(light: 0x232426, dark: 0x131416)   // --key-black
    static let keyLabel = Color(light: 0x67696C, dark: 0x3C3D40)   // --key-label
    static let tlClose = Color(light: 0xF45249, dark: 0xF45249)   // --tl-close
    static let tlMin = Color(light: 0xF6B324, dark: 0xF6B324)   // --tl-min
    static let tlZoom = Color(light: 0x4CC157, dark: 0x4CC157)   // --tl-zoom
    static let tlOff = Color(light: 0xC9CACC, dark: 0x46484A)   // --tl-off
    static let wave = Color(light: 0x79818D, lightAlpha: 0.55, dark: 0xBABEC4, darkAlpha: 0.4)   // --wave
    static let wavePlayed = Color(light: 0x0076ED, lightAlpha: 0.75, dark: 0x429AFE, darkAlpha: 0.8)   // --wave-played
    static let playhead = Color(light: 0xD02C2A, dark: 0xF75D59)   // --playhead
    static let scan = Color(light: 0x0076ED, lightAlpha: 0.18, dark: 0x429AFE, darkAlpha: 0.2)   // --scan
    static let waveSel = Color(light: 0x0E66C8, lightAlpha: 0.85, dark: 0x69AEFF, darkAlpha: 0.9)   // --wave-sel
    static let regionFill = Color(light: 0x0076ED, lightAlpha: 0.1, dark: 0x1485F4, darkAlpha: 0.14)   // --region-fill
    static let regionDim = Color(light: 0xF6F7F8, lightAlpha: 0.62, dark: 0x0F0F11, darkAlpha: 0.62)   // --region-dim
    static let handle = Color(light: 0x0076ED, dark: 0x3293FC)   // --handle
}

/// Instrument family → colour (InstrumentChipsView families; "all" = Basic Pitch single track).
enum InstrumentColor {
    static func color(forFamily family: String) -> Color {
        switch family {
        case "keys": return Token.instPiano
        case "guitars": return Token.instGuitar
        case "bass": return Token.instBass
        case "drums": return Token.instDrums
        case "strings": return Token.instStrings
        case "winds": return Token.instWoodwinds
        case "brass": return Token.instBrass
        case "synth": return Token.instSynth
        case "voice": return Token.instVoice
        default: return Token.instAll
        }
    }
}

/// Spacing (4 pt grid), radii and sizes from tokens.css. Points, not pixels.
enum Metric {
    static let sp1: CGFloat = 2   // --sp-1
    static let sp2: CGFloat = 4   // --sp-2
    static let sp3: CGFloat = 6   // --sp-3
    static let sp4: CGFloat = 8   // --sp-4
    static let sp5: CGFloat = 12   // --sp-5
    static let sp6: CGFloat = 16   // --sp-6
    static let sp7: CGFloat = 20   // --sp-7
    static let sp8: CGFloat = 24   // --sp-8
    static let sp9: CGFloat = 32   // --sp-9
    static let sp10: CGFloat = 48   // --sp-10
    static let controlH: CGFloat = 24   // --control-h
    static let controlHLg: CGFloat = 28   // --control-h-lg
    static let toolbarH: CGFloat = 52   // --toolbar-h
    static let sidebarW: CGFloat = 248   // --sidebar-w
    static let inspectorW: CGFloat = 280   // --inspector-w
    static let rowH: CGFloat = 12   // --row-h
    static let keysW: CGFloat = 56   // --keys-w
    static let rulerH: CGFloat = 26   // --ruler-h
    static let waveH: CGFloat = 64   // --wave-h
    static let overviewH: CGFloat = 96   // --overview-h
    static let handleW: CGFloat = 10   // --handle-w
    static let progressH: CGFloat = 6   // --progress-h
    static let ppsDefault: CGFloat = 90   // --pps-default
    static let traffic: CGFloat = 12   // --traffic
    static let icon: CGFloat = 16   // --icon
    static let iconSm: CGFloat = 12   // --icon-sm
    static let hairline: CGFloat = 1   // --hairline
    static let ringW: CGFloat = 3   // --ring-w
    static let windowMaxW: CGFloat = 1360   // --window-max-w
    static let windowMaxH: CGFloat = 860   // --window-max-h
    static let windowMinW: CGFloat = 960   // --window-min-w
    static let windowMinH: CGFloat = 600   // --window-min-h
    static let menubarH: CGFloat = 26   // --menubar-h
    static let menuW: CGFloat = 260   // --menu-w
    static let appIcon: CGFloat = 64   // --app-icon
    static let appIconLg: CGFloat = 112   // --app-icon-lg
    static let velH: CGFloat = 72   // --vel-h
    static let sheetW: CGFloat = 440   // --sheet-w
    static let settingsW: CGFloat = 640   // --settings-w
    static let rWindow: CGFloat = 16   // --r-window
    static let rPanel: CGFloat = 14   // --r-panel
    static let rControl: CGFloat = 6   // --r-control
    static let rCapsule: CGFloat = 999   // --r-capsule
    static let rRow: CGFloat = 8   // --r-row
    static let rNote: CGFloat = 3   // --r-note
    static let rSheet: CGFloat = 18   // --r-sheet
    static let blurGlass: CGFloat = 28   // --blur-glass
}

/// Type scale — use system text styles; these sizes are what the prototype renders at.
enum TypeScale {
    static let micro: CGFloat = 10   // --fs-micro
    static let caption: CGFloat = 11   // --fs-caption
    static let body: CGFloat = 13   // --fs-body
    static let headline: CGFloat = 13   // --fs-headline
    static let title3: CGFloat = 15   // --fs-title3
    static let title2: CGFloat = 17   // --fs-title2
    static let title: CGFloat = 22   // --fs-title
    static let large: CGFloat = 26   // --fs-large
    // Mapping: micro → .caption2, caption → .caption, body/headline → .body/.headline,
    // title3 → .title3, title2 → .title2, title → .title, large → .largeTitle
}
