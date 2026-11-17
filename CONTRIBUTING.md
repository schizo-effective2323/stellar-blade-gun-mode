# Contributing

## Branches

- **main**: tested releases only. Nobody pushes to it directly.
- **dev**: where work comes together. Pull requests go here.
- Your work: a branch in **your fork** (or in this repo if you have write access), named after what it does,
  e.g. `fix/rifle-fold`, `feat/reticle`, `anim/run-cycle`.

## How to send a change

1. Fork this repo (tick "copy all branches" so you get `dev`), or `git pull` the latest `dev` if you already have it.
2. Branch off `dev`: `git switch dev && git pull && git switch -c feat/your-thing`.
3. Commit small, focused changes with a message that says what changed and why.
4. Push the branch and open a pull request **into `dev`** (not `main`).
5. Say in the PR what you tested in game, and if any part comes from someone else, whose it is and under which license.

When `dev` has been tested in game, it is merged into `main` and tagged as a release.

## Rules

- **No game files** in the repo: no extracted/cooked assets, paks, tables or audio. Patches and scripts only.
- **No decompiled game code.** Findings (what a function does, offsets, behaviour) are fine in `docs/`; Ghidra output is not.
- **No personal email addresses** in commits. Use your GitHub no-reply address
  (`git config user.email "<id>+<name>@users.noreply.github.com"`).
- Never force-push to `main` or `dev`.

## Testing

Say which game build, which UE4SS build and which other mods were loaded. Many crashes seen so far happen inside
UE4SS while the mod's per-frame hook calls into the game; when you add anything to the tick, keep it to EVE's own
objects and keep it cheap.
