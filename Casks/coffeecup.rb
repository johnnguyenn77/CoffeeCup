cask "coffeecup" do
  version "1.0.3"
  sha256 "418628b2c7c037a2cb38b3e97b67bf8838267f66a43f5d59d3aebe4746faffae"

  url "https://github.com/johnnguyenn77/CoffeeCup/releases/download/v#{version}/CoffeeCup.dmg"
  name "CoffeeCup"
  desc "Menu bar app for toggling caffeinate"
  homepage "https://github.com/johnnguyenn77/CoffeeCup"

  depends_on macos: :ventura

  app "CoffeeCup.app"
end
