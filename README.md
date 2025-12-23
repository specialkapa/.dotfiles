# dotfiles

This is where I maintain my dotfiles. The approach I am using this blog post
https://www.jakewiesler.com/blog/managing-dotfiles which leverages the `stow` package.

> [!NOTE]
> [$HOME](../..) should be the target directory.

> [!NOTE]
> [$HOME/.dotfiles](..) is the `stow` directory.

# instructions

When setting up a machine from scratch.

> [!IMPORTANT]
> You might have to do other things before any of the below steps. For example use
> `atlasformer` if using a TNP laptop.

> [!IMPORTANT]
> You need to install all the `neovim` dependencies. Refer to
> [README](./nvim/.config/nvim/README.md) for details.

1. clone this repository.
2. the run the following:

```bash
cd $HOME/.dotfiles
stow bat
stow git-graph
stow lazygit
stow nvim
stow vim
stow vimwiki
````
