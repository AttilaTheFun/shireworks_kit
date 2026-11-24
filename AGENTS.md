# Shireworks Kit, for agents

The capabilities an app developed through Shireworks builds in, one library
each (README). Shake's design is docs/shake/Design.md, Updates'
docs/updates/Updates.md and its installer's docs/updates/Installing.md,
Crashes' docs/crashes/README.md.

- **This repository is public.** Never add a person's name (write "the
  owner"), a device or host name, a real IP address or hostname, a private
  project's name, or any secret, key, token, team ID or UDID. The
  exceptions, by the owner's choice: the two `logan-shire-shake` apps' names
  and client ids (public identifiers, not secrets; docs/shake/Design.md,
  section 5). Never a client secret.
- **Nothing goes to main but through a pull request,** branched from main
  (squash merges conflict with stacked PRs), adding a `changes/<branch>.md`
  fragment; never edit CHANGELOG.md. Merges are New Container Helper's,
  once CI is green; .github/ needs the owner's review. Don't request the
  owner's review otherwise.
- **Workflow files:** agents can't push `.github/workflows/`. Put the change
  in the PR body, and ask New Container Helper to commit it.
- **Versions are tags,** `vMAJOR.MINOR.PATCH`, which apps pin `exact:`. A tag
  is the owner's: Release in Reviews makes it. One release a minor line.
- **Portable:** `swift test` passes on Linux and on a Mac. Apple's frameworks
  stay behind `canImport`, in as few files as possible.
- **No builds on the owner's Macs:** build and test in a leased container or
  VM.
