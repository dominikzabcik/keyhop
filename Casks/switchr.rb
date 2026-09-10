# Homebrew cask for the Mac app. Install with:
#   brew tap dominikzabcik/switchr https://github.com/dominikzabcik/switchr
#   brew install --cask switchr
# Switchr updates itself, so the cask always points at the latest release.
cask "switchr" do
  version :latest
  sha256 :no_check

  url "https://github.com/dominikzabcik/switchr/releases/latest/download/Switchr.dmg"
  name "Switchr"
  desc "Switch Claude Code, Cursor and Codex accounts from the menu bar"
  homepage "https://github.com/dominikzabcik/switchr"

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Switchr.app"

  zap trash: [
    "~/Library/Application Support/Switchr",
    "~/Library/Preferences/dev.switchr.app.plist",
  ]
end
