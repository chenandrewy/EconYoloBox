# Renaming the top-level dirs (workspace/ must go)

Current: cellar/ (research library), workspace/ (active projects),
done/ (finished + retired). "workspace" collides with devcontainer
`${localWorkspaceFolder}`, VS Code workspaces, etc.

## Front-runners (Andrew's picks so far)

- cellar / workshop / hangar  <- leaning
- cellar / kitchen / attic

(spelling: hangar = aircraft building; hanger = coat hanger)

## Rejected / notes

- studio: grep noise (rstudio.com, visualstudio, Mac-Studio hostname in tools/ai-sesh)
- workshop: 21 hits, all LaTeX Workshop (james-yu.latex-workshop ext id,
  latex-workshop.* settings keys). Mild. Search `/workshop/` to dodge.
- porch: fun but not storage. done/ has to feel like storage.
- attic: fine, safe, a bit dull.
- study: collides with "the study" in research prose.
- kitchen, attic, hangar, porch etc: 0 hits in repo.

## Wider brainstorm (0928, all 0 whole-word hits outside journal)

- seedbank / field / granary  (farm; field has 10 hits, generic word)
- chartroom / deck / harbor   (ship)
- quarry / forge / armory     (smith; forge ~ conda-forge in the ecosystem)
- cave / atelier / grenier    (French: cellar / workshop / attic)
- armarium / scriptorium / reliquary  (monastery; long)
- meadow / hive / larder      (bees)
- observatory / launchpad / orbit  (space)
- one-off done/ swaps: hoard, vault, harbor, granary

## Went with cellar / workshop / hangar (0928)

Done: 0f92cc1 rename. Then made most refs name-free: 8f060eb (comments,
ybox test uses tools/), 99f7cde (README overview + .gitignore generic),
1bd1438 (cchat-yolo strips any top-level folder), bd6faae (.ignore no longer
re-includes workshop/).

## How to rename workshop/ again (e.g. -> kitchen/)

- host: `mv workshop kitchen` (stop containers first)
- repo: .gitignore, agents/YOLOBOX-CLAUDE.md (key paths + env section),
  README.md steps 5-6. (.ignore only names cellar/ now.)
- macuser: Shell-rc/aliases.zsh, the one `YBX_PROJECTS=` line (cdk, cdy,
  ssfinder all read it; macuser f364878).
- macOS: `defaults write com.apple.screencapture location .../1-SANDBOX/kitchen/dev/screenshots`
- not needed: macuser tests/test_cc_remote.py (workshop there is a fixture
  name), LaTeX Workshop comments, host/setup.sh.
