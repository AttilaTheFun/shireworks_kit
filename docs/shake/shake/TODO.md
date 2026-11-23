# To do

- **Switch the shared sign-in to a GitHub App once GitHub lets App user
  tokens upload attachments.** ShakeKit files with the owner's apps' shared
  sign-in, an OAuth App, because the
  attachment endpoint (`uploads.github.com/user-attachments/assets`)
  refuses GitHub App tokens. The GitHub App, `logan-shire-shake` (client id
`Iv23liWyhH9QbD6m7yx3`, as opposed to the OAuth App's `Ov23liV9P5ku0ntejoEc`),
already exists, and
  a GitHub App's user token would be narrower: Issues only, on the
  repositories it's installed on, expiring. `GitHubAuth` handles both kinds
  of token, so the switch is a configuration change per app. The evidence:
  - cli/cli#14495: GitHub's CLI maintainers say only first-party apps mint
    App user tokens the endpoint accepts, and no setting enables it;
  - cli/cli#14309: the open request to allow App tokens;
  - cli/cli#14516: `gh` lets the endpoint decide for `ghu_` tokens;
  - docs/Design.md, section 4: our own tests (2026-11-23).
