# Git Branch Tracker

A small interactive script to manage which remote branches Git tracks. This is especially useful for large repositories like Odoo, where thousands of remote branches exist but only a small subset is relevant to daily development.

The script reduces unnecessary fetching and keeps the local remote-tracking branch list manageable.

## Features

- Automatically detects the latest 3 numeric release branches (e.g. `18.0`, `19.0`, `20.0`).
- Detects related SaaS branches.
- Lets you interactively select release and SaaS branches.
- Supports developer-specific branch suffixes (e.g. `-djip`, `-fw`).
- Keeps `master` by default.
- Updates the remote's fetch configuration based on your selection.
- Removes unselected remote-tracking references locally.
- Enables pruning and disables automatic tag fetching.

## Requirements

- Bash 4+
- Git
- An interactive terminal
- At least one configured Git remote

## Usage

Run the script using its absolute path **from inside the repository's working tree**:

```bash
bash /home/odoo/download/edit-git-config.sh
```

You do not need to close your repository, enter its `.git` directory, or copy the script into the repository.

The script operates on the repository from which it is invoked.

### Interactive controls

| Key | Action |
|---|---|
| Up / Down | Navigate |
| Space | Toggle selection |
| `a` | Select all |
| `n` | Select none |
| Enter | Continue |
| `q` | Cancel |

### Developer suffixes

You can configure which developer-specific branches to track.

- Type a suffix and press Enter to add it.
- Use Up / Down and Delete to remove a selected suffix.
- Backspace removes the last suffix.
- Space continues.
- Esc cancels.

By default, the script uses `-djip` and `-fw`, unless it can infer existing suffixes from the current fetch configuration.

You can override the defaults:

```bash
DEFAULT_DEVELOPERS="-alice -team" bash /home/odoo/download/edit-git-config.sh
```

## Exceptional branches

Sometimes you need a branch that does not match the selected release or developer suffix patterns.

You can fetch and check out such a branch without permanently adding it to the remote's fetch configuration:

```bash
BRANCH=master-imp-test-roboodo
REMOTE=odoo-dev

git fetch "$REMOTE" "+refs/heads/$BRANCH:refs/remotes/$REMOTE/$BRANCH" &&
git switch --track -c "$BRANCH" "$REMOTE/$BRANCH"
```

This creates a local branch and sets its upstream.

**Why not add a permanent fetch refspec?**

An exact refspec for an exceptional branch can cause future fetch operations to fail if that branch is deleted from the remote.

By fetching it explicitly without changing the remote's fetch configuration:

- You can check out the exceptional branch.
- Normal `git fetch` and `git remote update` remain unaffected.
- The local branch is not deleted.
- To update the exceptional branch later, fetch it explicitly again.

Note: Because the exceptional branch is not part of the regular fetch configuration, its remote-tracking reference will not be automatically updated or pruned by normal fetch operations.

## What changes does the script make?

The script modifies only the current repository's local Git configuration and remote-tracking references.

It:
- Updates `remote.<name>.fetch`.
- Enables `remote.<name>.prune`.
- Sets `remote.<name>.tagOpt` to `--no-tags`.
- Fetches the selected branches.
- Deletes unselected references under `refs/remotes/`.

It does **not**:
- Delete actual local branches under `refs/heads/`.
- Delete branches from the remote server.
- Push any changes to the remote.
- Run `git gc`.

Review the preview carefully before confirming. Manually created remote-tracking references that are not included in the selection may also be removed.

## Pros

- Reduces unnecessary downloads, especially in large repositories.
- Makes regular fetches faster.
- Keeps the remote-tracking branch list clean.
- Gives you control over which release and developer branches are tracked.

## Cons

- Branches outside the selected patterns must be fetched explicitly when needed.
- New Odoo releases require rerunning the script to include them.
- Exceptional branches need to be fetched explicitly again when you want to update them.

## Links

- [Tracking script](https://github.com/dhruv4023/scripts/blob/dev/git/edit-git-config.sh)
- [Script README](https://github.com/dhruv4023/scripts/blob/dev/git/readme.md)
