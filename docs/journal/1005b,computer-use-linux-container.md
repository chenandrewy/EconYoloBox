# Computer Use does not work right now in the Linux container

Date: 2026-10-05. Notes from today's discussion; no implementation or configuration change.

The question was whether Codex CLI running inside this Linux devcontainer can use OpenAI's Computer Use plugin. The practical answer for this setup is **no**: there is no supported Linux build of that native desktop-control plugin to run in the container. The plugin depends on platform-native desktop accessibility integration. The public OpenAI plugin catalog currently describes Computer Use as controlling Mac apps; it does not document a Linux container installation. The user's stated platform scope was macOS and Windows, but the exact Windows details were not verified here.

The checkout also has a separate local restriction: `agents/managed/YOLOBOX-codex-requirements.toml` disables apps, plugins, and remote plugins, and allows no marketplace sources. That policy would prevent using a plugin in this container even if a compatible build became available, unless the policy were deliberately changed.

OpenAI's API computer-use guidance describes a different pattern in which a developer supplies the browser or desktop environment, including a Playwright browser. That is not a built-in Computer Use capability of Linux Codex CLI. We discussed a proposal to install Chromium and Playwright and drive them through Codex shell commands; the user rejected that plan, and `docs/journal/plan-computer-use.md` was deleted. Do not revive it as though it were the agreed next step.

Two older archived entries remain as historical context: `archive/0731b,scholar-host-browser-test.md` first proposed a browser inside the devcontainer, and `archive/0823a,photo-labeler-browser-tooling.md` refined that proposal for testing and screenshots. They concern custom browser tooling, not OpenAI's native Computer Use plugin, and neither records an installation. A search of all 112 Markdown journal entries found no earlier entry explicitly discussing OpenAI Computer Use or its Linux Codex CLI availability. `archive/0726b,codex-devcontainer-remote.md` concerns remote access **to** Codex, not Codex controlling a computer.

References checked in this discussion:

- OpenAI plugin catalog: https://developers.openai.com/plugins
- OpenAI API computer-use guide: https://developers.openai.com/api/docs/guides/tools-computer-use
- Local managed policy: `agents/managed/YOLOBOX-codex-requirements.toml`
