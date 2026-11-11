extends RefCounted
## Which build this is. The web build on GitHub replaces "dev" with the
## commit (see .github/workflows/build.yml) and publishes the same text in
## version.txt next to the game, so the start menu can spot a newer one.
const VERSION := "dev"
