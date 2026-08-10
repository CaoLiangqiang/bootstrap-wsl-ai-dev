# Optional Starship Terminal Prompt

Use the independent `setup-starship-catppuccin` Skill as the implementation and asset authority. This repository only provides an opt-in adapter so WSL bootstrap users can include terminal presentation without duplicating scripts, font binaries, licenses, or theme configuration.

## Install both skills

Install `bootstrap-wsl-ai-dev` and `setup-starship-catppuccin` at the same user scope. The adapter searches:

```bash
npx skills add https://github.com/CaoLiangqiang/setup-starship-catppuccin/tree/v0.1.0 \
  --skill setup-starship-catppuccin \
  --agent codex \
  --global \
  --yes
```

`v0.1.0` is the minimum release-qualified dependency for this adapter. Use an immutable tag URL for reproducible installation.

1. `--skill-dir PATH`
2. `SETUP_STARSHIP_CATPPUCCIN_DIR`
3. a sibling checkout
4. `${CODEX_HOME:-$HOME/.codex}/skills/setup-starship-catppuccin`
5. `~/.agents/skills/setup-starship-catppuccin`

## Audit and install

Start read-only:

```bash
bash scripts/configure-starship-prompt.sh --check
```

Configure the WSL user only:

```bash
bash scripts/configure-starship-prompt.sh --install
```

Configure both WSL shells and the Windows host after explicit approval:

```bash
bash scripts/configure-starship-prompt.sh --install --with-windows
```

Pass `--shells bash,zsh,fish` to choose an explicit shell set. Use `--skill-dir` when developing both repositories outside a standard Skill installation layout.

## Boundary

- Keep this feature independent from PATH isolation, startup baseline, Windows Explorer integration, proxy, Docker, and AI CLI migration.
- Do not install it as part of the default bootstrap workflow.
- Let the standalone Skill own backups, markers, theme assets, fonts, Windows Terminal JSON changes, validation, and rollback.
- Do not vendor CaskaydiaCove font binaries into this repository. The standalone repository carries the required SIL OFL license and checksums.
- Close all Windows Terminal windows after a Windows install so the process reloads the user PATH and fonts.
