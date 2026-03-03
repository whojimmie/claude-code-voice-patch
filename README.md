# Claude Voice Patcher

> **Disclaimer**: This is a personal experiment and is not affiliated with or endorsed by Anthropic. Patching the Claude Code binary may violate [Anthropic's Terms of Service](https://www.anthropic.com/legal/consumer-terms). Use at your own risk. Don't use this in production environments.

Enables the hidden `/voice` command in [Claude Code](https://claude.ai/code) by patching the installed binary.

## Background

Claude Code has a built-in voice mode (`/voice`) that lets you dictate to Claude using your microphone. It's gated behind a GrowthBook A/B flag (`tengu_amber_quartz`) that is off by default. This script patches the installed binary to bypass both the feature flag and the visibility gate, making `/voice` appear in the command menu.

## Requirements

- Claude Code installed (`claude` in your PATH)
- Python 3 (pre-installed on macOS/Linux)
- macOS or Linux (Windows: use WSL)
- A Claude.ai account with an active subscription (voice requires OAuth login, not an API key)
- [SoX](https://sox.sourceforge.net/) for microphone capture:
  ```bash
  # macOS
  brew install sox

  # Ubuntu/Debian
  sudo apt install sox
  ```

## Usage

```bash
./patch-voice.sh
```

The script will:
1. Detect your installed `claude` binary and version
2. Patch it (creates a new file, never modifies the original)
3. Sign the binary (macOS only — not needed on Linux)
4. Verify it starts correctly
5. Ask how you want to use it:

```
How do you want to use the patched binary?

  1) Replace 'claude' symlink   — 'claude' uses voice-patched binary
  2) Add 'claude-voice' symlink — keeps original 'claude', adds new command
  3) Do nothing                 — binary is at <path>
```

## Using Voice Mode

Once patched, open Claude Code and run `/voice` to toggle voice mode on/off (make sure it's enabled). Run it again to open the voice interface — hold **Space** to record, release to transcribe.

> The orange microphone indicator in your macOS menu bar confirms the mic is active while recording.

## Notes

**Auto-update**: If you chose option 1 (symlink), running `claude update` will revert the symlink to the new official binary. Re-run the script after updating to re-patch.

**Sharing**: The patched binary is ad-hoc signed (macOS) and only works on the machine it was created on. Friends should run this script themselves.

**Version compatibility**: The script dynamically finds the relevant function names via regex — it doesn't hardcode anything version-specific. If your installed version doesn't include voice support yet, the script will say so and exit without making any changes.

**Reverting**: The original binary is never modified. To go back:

```bash
# Easiest — just update Claude:
claude update

# Or find the original binary path and restore manually:
ls -la $(which claude)          # shows where the symlink points
ln -sf <original-path> $(which claude)
```
