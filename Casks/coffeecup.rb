cask "coffeecup" do
  version "1.0.4"
  sha256 "84d9c7bb41bcc790f052627b3e366767d613c60b3109a458f382a3b5736c7990"

  url "https://github.com/johnnguyenn77/CoffeeCup/releases/download/v#{version}/CoffeeCup.dmg"
  name "CoffeeCup"
  desc "Keep your Mac display awake from the menu bar"
  homepage "https://github.com/johnnguyenn77/CoffeeCup"

  depends_on macos: :ventura

  app "CoffeeCup.app"
end
