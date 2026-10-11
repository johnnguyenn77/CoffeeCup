cask "coffeecup" do
  version "1.0.9"
  sha256 "9af6aa11bd1f61f09fb236211002440c598af7e0771dee5247d950e26956c581"

  url "https://github.com/johnnguyenn77/CoffeeCup/releases/download/v#{version}/CoffeeCup.dmg"
  name "CoffeeCup"
  desc "Keep your Mac display awake from the menu bar"
  homepage "https://github.com/johnnguyenn77/CoffeeCup"

  depends_on macos: :ventura

  app "CoffeeCup.app"
end
