cask "coffeecup" do
  version "1.0.5"
  sha256 "df6fb10571313c08a8bc2e2c0667a1f22e7de9bb67fea490fe6566f37e5d407e"

  url "https://github.com/johnnguyenn77/CoffeeCup/releases/download/v#{version}/CoffeeCup.dmg"
  name "CoffeeCup"
  desc "Keep your Mac display awake from the menu bar"
  homepage "https://github.com/johnnguyenn77/CoffeeCup"

  depends_on macos: :ventura

  app "CoffeeCup.app"
end
