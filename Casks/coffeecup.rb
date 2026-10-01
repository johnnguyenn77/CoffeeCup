cask "coffeecup" do
  version "1.0.6"
  sha256 "5ae6661cf61c2799dbdb7fef5a2f8040f494cdcda27b16f2a40874aadc18a3db"

  url "https://github.com/johnnguyenn77/CoffeeCup/releases/download/v#{version}/CoffeeCup.dmg"
  name "CoffeeCup"
  desc "Keep your Mac display awake from the menu bar"
  homepage "https://github.com/johnnguyenn77/CoffeeCup"

  depends_on macos: :ventura

  app "CoffeeCup.app"
end
