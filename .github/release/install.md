## Install

Requires **macOS 26 or later on a Mac with Apple silicon**. This build is not made for Intel Macs.

1. Download `SillyMIDITools-__VERSION__-macOS-arm64.zip` and **unzip it by double-clicking in Finder** (or `ditto -x -k SillyMIDITools-__VERSION__-macOS-arm64.zip .`). Plain `unzip` drops signature data from the bundled Metal libraries.
2. Move `SillyMIDITools.app` to `/Applications`.
3. The app is ad-hoc signed and not notarized, so clear the quarantine flag once:
   ```sh
   xattr -dr com.apple.quarantine /Applications/SillyMIDITools.app
   ```
   Or open the app and choose **Open Anyway** in System Settings, Privacy & Security.
4. Press **Continue** on the Welcome sheet and choose a working folder, drop an audio file on the window and press **Transcribe**.

SHA-256 of the zip: `__SHA256__`
