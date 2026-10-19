cask "coffeecup" do
  version "1.0.11"
  sha256 "695a3c2ef9ee58d2c9027404adb5ccd0737d00a23945166a885882d42dc75ce8"

  url "https://github.com/johnnguyenn77/CoffeeCup/releases/download/v#{version}/CoffeeCup.dmg"
  name "CoffeeCup"
  desc "Keep your Mac display awake from the menu bar"
  homepage "https://github.com/johnnguyenn77/CoffeeCup"

  depends_on macos: :ventura

  app "CoffeeCup.app"
end
