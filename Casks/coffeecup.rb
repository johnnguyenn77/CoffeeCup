cask "coffeecup" do
  version "1.0.3"
  # The release workflow replaces this with the SHA-256 of the published DMG.
  sha256 :no_check

  url "https://github.com/johnnguyenn77/CoffeeCup/releases/download/v#{version}/CoffeeCup.dmg"
  name "CoffeeCup"
  desc "Menu bar app for toggling caffeinate"
  homepage "https://github.com/johnnguyenn77/CoffeeCup"

  depends_on macos: :ventura

  app "CoffeeCup.app"
end
