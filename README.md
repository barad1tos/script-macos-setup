![Banner](art/banner-2x.png)

## Introduction

This repository serves as my way to help me set up and maintain my Mac. It takes the effort out of installing everything manually. Everything needed to install my preferred setup of macOS is detailed in this readme. Feel free to explore, learn, and copy parts for your own dotfiles. Enjoy!

📖 - [Read the blog post](https://driesvints.com/blog/getting-started-with-dotfiles)  
📺 - [Watch the screencast on Laracasts](https://laracasts.com/series/guest-spotlight/episodes/1)  
💡 - [Learn how to build your own dotfiles](https://github.com/driesvints/dotfiles#your-own-dotfiles)

If you find this repo useful, [consider sponsoring me](https://github.com/sponsors/driesvints) (a little bit)! ❤️

## Repository Structure

```bash
script-macos-setup/
├── setup              # Main entry point (executable)
├── Brewfile           # Homebrew packages
├── modules/           # Setup modules
│   ├── _functions.sh  # Shared utilities
│   ├── cleanup-state.sh
│   ├── preflight.sh
│   ├── xcode.sh
│   ├── homebrew.sh
│   ├── 1password.sh
│   ├── dotfiles.sh
│   ├── macos.sh
│   ├── mackup.sh
│   ├── verify.sh
│   └── cleanup.sh
└── art/               # README assets
```

**Philosophy**: Minimal, elegant structure. Single `modules/` directory for all setup scripts, executable `setup` entry point following UNIX convention (like `git`, `docker`).

## A Fresh macOS Setup

These instructions are for setting up new Mac devices. Instead, if you want to get started building your own dotfiles, you can [find those instructions below](#your-own-dotfiles).

### Backup your data

If you're migrating from an existing Mac, you should first make sure to backup all of your existing data. Go through the checklist below to make sure you didn't forget anything before you migrate.

- Did you commit and push any changes/branches to your git repositories?
- Did you remember to save all important documents from non-iCloud directories?
- Did you save all of your work from apps which aren't synced through iCloud?
- Did you remember to export important data from your local database?
- Did you update [mackup](https://github.com/lra/mackup) to the latest version and ran `mackup backup`?

### Setting up your Mac

After backing up your old Mac, you may now follow these install instructions to set up a new one.

1. Update macOS to the latest version through system preferences
2. Set up an SSH key by using one of the two following methods
   2.1. If you use 1Password, install it with the 1Password [SSH agent](https://developer.1password.com/docs/ssh/get-started/#step-3-turn-on-the-1password-ssh-agent) and sync your SSH keys locally.
   2.2. Otherwise, [generate a new public and private SSH key](https://docs.github.com/en/github/authenticating-to-github/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent) by running:

   ```zsh
   curl https://raw.githubusercontent.com/driesvints/dotfiles/HEAD/ssh.sh | sh -s "<your-email-address>"
   ```

3. Clone this repo to `~/.dotfiles` with:

    ```zsh
    git clone --recursive git@github.com:driesvints/dotfiles.git ~/.dotfiles
    ```

4. Run the installation with:

    ```zsh
    cd ~/.dotfiles && ./setup
    ```

5. Start `Herd.app` and run its install process
6. After mackup is synced with your cloud storage, restore preferences by running `mackup restore`
7. Restart your computer to finalize the process

Your Mac is now ready to use!

> 💡 You can use a different location than `~/.dotfiles` if you want. Make sure you also update the references in your dotfiles configuration and the [`setup`](./setup) file.

### Cleaning your old Mac (optionally)

After you've set up your new Mac, you may want to wipe and clean install your old Mac. Follow [this article](https://support.apple.com/guide/mac-help/erase-and-reinstall-macos-mh27903/mac) to do that. Remember to [backup your data](#backup-your-data) first!

## Customization

If you want to customize this setup for your own needs, fork this repo and adjust it to your preferences.

### macOS System Preferences

The macOS system preferences are configured in `modules/macos.sh`. You can adjust the settings to your liking. For more settings, check out [the original script by Mathias Bynens](https://github.com/mathiasbynens/dotfiles/blob/master/.macos) and [Kevin Suttle's macOS Defaults project](https://github.com/kevinSuttle/MacOS-Defaults).

### Applications

Check out the [`Brewfile`](./Brewfile) file and adjust the apps you want to install for your machine. Use [Homebrew's search page](https://formulae.brew.sh/cask/) to check if the app you want to install is available.

### Dotfiles Integration

This setup includes a dotfiles module (`modules/dotfiles.sh`) that clones and installs your dotfiles from a separate repository. Configure your dotfiles repository URL in the module, or skip this step if you don't use dotfiles.

Enjoy your customized macOS setup!

## Hybrid Backup Strategy

This setup uses a **hybrid approach** combining Dotfiles (Git) and Mackup (iCloud) for maximum reliability and convenience.

### Configuration Management Philosophy

#### 🔧 Dotfiles (Git) - For CLI Configurations
- **Location:** `~/Library/Mobile Documents/com~apple~CloudDocs/3. Git/Own/dotfiles`
- **Manages:**
  - ZSH (`.zshrc`, `.zshenv`, functions, aliases)
  - Git (`.gitconfig`, `.gitignore_global`)
  - Bash (`.bashrc`, `.bash_profile`)
  - Vim/Neovim (init.vim, plugins)
  - P10k theme (`.p10k.zsh`)
- **Benefits:**
  - Git versioning (history, branches, rollback)
  - Pull requests and code review
  - Cross-platform compatibility

#### 📦 Mackup (iCloud) - For GUI Applications
- **Backup Directory:** `~/Library/Mobile Documents/com~apple~CloudDocs/2. Backup/mackup`
- **Manages:**
  - IDE settings (VS Code, PyCharm, Sublime Text)
  - Productivity tools (Raycast, Obsidian, Notion, Things3, Todoist)
  - Terminal emulators (Warp, Ghostty, iTerm2)
  - System utilities (Bartender, Hazel, Moom, PopClip, iStat Menus)
  - Communication apps (Slack, Discord, Telegram, WhatsApp)
- **Benefits:**
  - Automatic iCloud sync
  - No commits needed for GUI setting changes
  - Simple restore on new Mac

#### 🔐 Security Exclusions
The following sensitive data is **excluded** from Mackup:
- SSH keys (`~/.ssh/`)
- AWS credentials (`~/.aws/credentials`)
- Kubernetes configs (`~/.kube/*.yaml`)
- Docker registry credentials
- GCloud credentials

**Recommendation:** Use 1Password for storing secrets.

### Custom Mackup Applications

For applications without built-in Mackup support, custom configurations are created in `~/.mackup/`:

**Supported custom apps (3 total):**
- `reeder.cfg` - Reeder RSS reader feeds and preferences
- `warp.cfg` - Warp terminal settings and themes
- `zed.cfg` - Zed text editor configuration

**Note:** Most modern apps (Arc, Notion, Slack, Discord, etc.) sync settings via cloud authentication, so custom mackup configs are only needed for apps that store settings locally.

### Workflow Order

The `setup` script executes installation modules in the following order:
1. `cleanup-state.sh` - Cleanup previous setup state
2. `preflight.sh` - System checks and prerequisites
3. `xcode.sh` - Xcode Command Line Tools
4. `homebrew.sh` - Homebrew and packages
5. `1password.sh` - 1Password with SSH agent
6. `dotfiles.sh` - Clones dotfiles, installs CLI configs
7. `macos.sh` - macOS system preferences
8. `mackup.sh` - Configures Mackup, syncs GUI settings
9. `verify.sh` - Verification checks
10. `cleanup.sh` - Final cleanup and finalization

This order ensures no conflicts between systems.

### Why This Approach?

**Compared to Dotfiles only:**
- ✅ CLI configs with Git history
- ✅ GUI configs auto-synced (no manual copying)
- ✅ No need to commit every GUI preference change

**Compared to Mackup only:**
- ✅ CLI configs have full Git history
- ✅ Sensitive data excluded from sync
- ✅ Fine-grained control over what syncs

## Thanks To...

I first got the idea for starting this project by visiting the [GitHub does dotfiles](https://dotfiles.github.io/) project. Both [Zach Holman](https://github.com/holman/dotfiles) and [Mathias Bynens](https://github.com/mathiasbynens/dotfiles) were great sources of inspiration. [Sourabh Bajaj](https://twitter.com/sb2nov/)'s [Mac OS X Setup Guide](http://sourabhbajaj.com/mac-setup/) proved to be invaluable. Thanks to [@subnixr](https://github.com/subnixr) for [his awesome Zsh theme](https://github.com/subnixr/minimal)! Thanks to [Caneco](https://twitter.com/caneco) for the header in this readme. And lastly, I'd like to thank [Emma Fabre](https://twitter.com/anahkiasen) for [her excellent presentation on Homebrew](https://speakerdeck.com/anahkiasen/a-storm-homebrewin) which made me migrate a lot to a [`Brewfile`](./Brewfile) and [Mackup](https://github.com/lra/mackup).

In general, I'd like to thank every single one who open-sources their dotfiles for their effort to contribute something to the open-source community.
