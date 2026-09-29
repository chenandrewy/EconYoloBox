# Publishing this repo to EconYoloBox

2026-09-28. Stop hand-curating `workshop/aiworkflow/econyolobox`; push this repo
straight to EconYoloBox. Its 3 curated commits have unrelated history.

Chose force-push over rebase/graft (conflicts or SHA rewrite) and
`merge -s ours` (extra root). An archive branch keeps the old commits.

```
git remote add econyolobox https://github.com/chenandrewy/EconYoloBox.git
git fetch econyolobox
git push econyolobox econyolobox/main:refs/heads/archive/curated
git push --force econyolobox main:main
```

First merge `cleanup/reorg-rename` into `main`. Full history goes public.
