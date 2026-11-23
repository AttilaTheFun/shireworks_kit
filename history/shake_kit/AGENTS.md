# Shake Kit, for agents

ShakeKit and the libraries under it (GitHubAuth, GitHubIssues,
IssueComposer): docs/Design.md is the design.

- **This repository is public.** Never add a person's name (write "the
  owner"), a device or host name, a private project's name, or any secret,
  key, token, client id, team ID or UDID.
- **Nothing goes to main but through a pull request.** Each PR is branched
  from main (squash merges conflict with stacked PRs) and adds a
  `changes/<branch>.md` fragment; never edit CHANGELOG.md. Agents merge
  their own once CI is green and the branch is up to date, except those
  touching .github/, which need the owner's review. Don't request the
  owner's review otherwise.
- **Workflow files:** agents can't push `.github/workflows/`. Put the change
  in the PR body, and ask New Container Helper to commit it.
- **Versions are tags,** `vMAJOR.MINOR.PATCH`, which apps pin `exact:`. A tag
  is the owner's.
- **Portable:** `swift test` passes on Linux and on a Mac. Apple's frameworks
  stay behind `canImport`, in as few files as possible.
- **No builds on the owner's Macs:** build and test in a leased container or
  VM.
