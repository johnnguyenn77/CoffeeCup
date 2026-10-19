cask "coffeecup" do
  version "1.0.12"
  sha256 "1ab727a147f13a04ef4379ba8a60c0a6132be5a92ddc970e40db3d9f348960c8"

  url "https://github.com/johnnguyenn77/CoffeeCup/releases/download/v#{version}/CoffeeCup.dmg"
  name "CoffeeCup"
  desc "Keep your Mac display awake from the menu bar"
  homepage "https://github.com/johnnguyenn77/CoffeeCup"

  depends_on macos: :ventura

  app "CoffeeCup.app"
end
