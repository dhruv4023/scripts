# Git branch tracker configuration

`edit-git-config.sh` interactively narrows the branches fetched and tracked for every Git remote in the current repository. It is useful when a remote has many release, SaaS, and developer branches, but you only need a selected subset locally.

## Requirements

- Bash 4 or newer
- Git
- An interactive terminal
- At least one configured remote

## Run

From inside the repository whose remotes you want to configure:

```bash
/path/to/scripts/git/edit-git-config.sh
```

The script reads remote branches with `git ls-remote --heads`, then offers the three latest numeric `N.0` releases and their matching `saas-N.X` branches. Already configured branches are preselected.

Use the arrow keys to move through the release list, **Space** to toggle a branch, **a** to select all, **n** to select none, and **Enter** to continue. In the suffix editor, type a developer suffix and press **Enter** to add it; **Space** continues. Use **Up/Down** and **Delete** to remove an entry, or **Backspace** to remove the last entry. **Esc** cancels.

Developer suffixes are used to recognize feature branches under selected release bases. The script initializes the list in this order:

1. `DEFAULT_DEVELOPERS`, if set in the environment.
2. Suffixes inferred from existing remote fetch refspecs.
3. The built-in fallback suffixes `-djip -fw`.

For example, to start with a custom list:

```bash
DEFAULT_DEVELOPERS="-alice -team" /path/to/scripts/git/edit-git-config.sh
```

Suffix matching is case-sensitive and expects the suffix at the end of the branch name (for example, `19.0-fix-alice`).

## Review and apply

Before making changes, the script displays a per-remote preview of the fetch patterns, branches to keep, and local remote-tracking refs to remove. Review this plan and confirm at the prompt to apply it. Declining or pressing **q**/**Esc** in a selector exits without applying the plan.

When applied, the script:

- Rewrites each remote's `remote.<name>.fetch` refspecs to cover `master`, selected release/SaaS bases, and matching developer branches.
- Enables pruning for deleted server branches and disables tag fetching for those remotes.
- Fetches the selected branches, then deletes unselected **local remote-tracking refs**.

Local branches and branches on the server are not deleted. The script does not run `git gc`. Changes to fetch configuration are stored in the current repository's Git config.

Afterward, review local branch tracking with:

```bash
git branch -vv
```
