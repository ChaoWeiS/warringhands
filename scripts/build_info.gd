extends RefCounted
## Which build this is. The web build on GitHub replaces "dev" with the build
## number (1, 2, 3…; see .github/workflows/build.yml) and publishes it in
## version.txt next to the game, so the start menu can spot a newer one.
const VERSION := "dev"
