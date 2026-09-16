# Homebrew cask for the Mac app. Install with:
#   brew tap dominikzabcik/keyhop https://github.com/dominikzabcik/keyhop
#   brew install --cask keyhop
# Keyhop updates itself, so the cask always points at the latest release.
cask "keyhop" do
  version :latest
  sha256 :no_check

  url "https://github.com/dominikzabcik/keyhop/releases/latest/download/Keyhop.dmg"
  name "Keyhop"
  desc "Switch Claude Code, Cursor, Codex and Gemini CLI accounts from the menu bar"
  homepage "https://github.com/dominikzabcik/keyhop"

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Keyhop.app"
  # Linked as `keyhop`, the app binary answers as the command.
  binary "#{appdir}/Keyhop.app/Contents/MacOS/Keyhop", target: "keyhop"

  zap trash: [
    "~/Library/Application Support/Keyhop",
    "~/Library/Preferences/app.keyhop.app.plist",
  ]
end
