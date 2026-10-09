cask "coffeecup" do
  version "1.0.8"
  sha256 "c443027f4dfbc1fbf1d28d1fa587718e373319cb07cb599744e4ad8549b0f71b"

  url "https://github.com/johnnguyenn77/CoffeeCup/releases/download/v#{version}/CoffeeCup.dmg"
  name "CoffeeCup"
  desc "Keep your Mac display awake from the menu bar"
  homepage "https://github.com/johnnguyenn77/CoffeeCup"

  depends_on macos: :ventura

  app "CoffeeCup.app"
end
