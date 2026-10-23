cask "coffeecup" do
  version "1.0.13"
  sha256 "b624c2508e676de10ec86777e169dcab9f41b99c2c55b3e8c9692c27b05f56aa"

  url "https://github.com/johnnguyenn77/CoffeeCup/releases/download/v#{version}/CoffeeCup.dmg"
  name "CoffeeCup"
  desc "Keep your Mac display awake from the menu bar"
  homepage "https://github.com/johnnguyenn77/CoffeeCup"

  depends_on macos: :ventura

  app "CoffeeCup.app"
end
