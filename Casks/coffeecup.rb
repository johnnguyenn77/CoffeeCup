cask "coffeecup" do
  version "1.0.5"
  sha256 "66f7f083ba0ba1b9b13479e61cb61aaa326b6b6864d9e96b579740f543d56db8"

  url "https://github.com/johnnguyenn77/CoffeeCup/releases/download/v#{version}/CoffeeCup.dmg"
  name "CoffeeCup"
  desc "Keep your Mac display awake from the menu bar"
  homepage "https://github.com/johnnguyenn77/CoffeeCup"

  depends_on macos: :ventura

  app "CoffeeCup.app"
end
