cask "coffeecup" do
  version "1.0.7"
  sha256 "df15a8ac6d2a27bbdea8960b585c91223ff603776fc893499e28676dd3189b7a"

  url "https://github.com/johnnguyenn77/CoffeeCup/releases/download/v#{version}/CoffeeCup.dmg"
  name "CoffeeCup"
  desc "Keep your Mac display awake from the menu bar"
  homepage "https://github.com/johnnguyenn77/CoffeeCup"

  depends_on macos: :ventura

  app "CoffeeCup.app"
end
