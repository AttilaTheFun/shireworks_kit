# Shake Kit: design

ShakeKit lets someone testing an app file a bug from inside it. They shake
the phone (or pick Report a Bug… on a Mac), and a sheet shows a screenshot
of the moment, the app's recent logs and its version. They sign in to
GitHub once, add a title and a few words, and ShakeKit opens an issue in
the app's repository, with the screenshots embedded inline as GitHub's own
attachments.

The issue composer, the attachment upload and the GitHub client are
general, not shake-specific. They're public libraries here, which the
owner's other apps (an issues browser among them) can use too. ShakeKit is
the thin part on top: the shake, the screenshot and the logs.

**Decided** (by the owner, November 2026):
- Apple's platforms come first; other hosts are later.
- Markup comes later.
- The app gives the repository.
- Attachments are GitHub's own, inline, through an **OAuth App** with
  device flow (sections 4 and 5). It switches to a GitHub App when GitHub
  allows that (TODO.md).

## 1. Libraries

One repository and one Swift package, with four products. Each depends
only on the ones above it.

| Product | What it is | Used by |
| --- | --- | --- |
| `GitHubAuth` | Device flow, tokens, refresh, keychain store | everything below; any app that signs in to GitHub |
| `GitHubIssues` | REST client: create, edit and comment on issues; upload attachments (section 4); labels | ShakeKit; an issues browser |
| `IssueComposer` | SwiftUI: title, Markdown body, attachments with thumbnails (add, remove, reorder), preview, submit, the draft kept on failure | ShakeKit; an issues browser's "New Issue" and "Comment" |
| `ShakeKit` | The shake (or menu command), the screenshot of the moment, logs, device info, and opening `IssueComposer` with them filled in | each app |

`GitHubAuth` and `GitHubIssues` are plain Swift, with no UI, tested with
`swift test` on Linux. `IssueComposer` and `ShakeKit` are SwiftUI, and
their view models are tested on Linux too.

**Shaped so an issues browser can adopt them without a rewrite:**
- **`GitHubIssues`:**
  - The types are `GitHubIssue`, `IssueComment`, `GitHubLabel` and
    `IssueChange` (`title`, `body`, `labels`, `state`, `stateReason`, all
    optional, with `isEmpty`). They match the owner's existing client in
    names, Codable keys and optionality.
  - The calls: create, update, close and reopen (with a reason), comment,
    edit and delete a comment, list labels, and upload an attachment.
- **`IssueComposer`:**
  - **Sending is the host's.** Submit is an `async throws` closure the
    host gives, so a host with an offline outbox can queue the issue
    instead of sending it.
  - **An accessory slot** (`@ViewBuilder`) beside title and body: an
    issues browser's kind, status and priority pickers; ShakeKit's device
    info.
  - **Drafts** are kept through a small protocol, which defaults to
    `UserDefaults`.
  - **Attachments upload at submit, not when picked:**
    1. Each attachment is uploaded.
    2. The body's placeholders are rewritten to the returned URLs.
    3. The host's submit is called.
    4. On failure, the draft and its local files are kept.
- **Kept in each host, not here:** its own issue model, label scheme,
  cache and outbox.

## 2. API

    import ShakeKit

    WindowGroup {
        ContentView()
            .shakeToReport(repository: "owner/app")
    }
    .commands { ShakeKitCommands() }   // macOS: Help › Report a Bug… (⌥⌘B)

- **iOS and iPadOS.** A shake (`motionEnded(.motionShake)`, reaching the
  key window through the responder chain) opens the composer. Shakes
  that come in while it's up are ignored.
- **macOS.** No shake: `ShakeKitCommands()` adds the menu command and its
  shortcut.
- **Other hosts:** later. The API is kept portable, so they can follow
  through Isomer.
- `ShakeReport.present(repository:)` opens it from code, for a "Report a
  Bug" button.
- `ShakeKitConfiguration` (optional): which log subsystems to include,
  the time window, size caps, extra redaction rules, and the issue's
  labels.

Used without ShakeKit, the composer looks like this:

    IssueComposer(repository: "owner/app", session: session)  // GitHubAuth session

## 3. The composer, as ShakeKit fills it

1. **Screenshot of the moment,** taken when the shake arrives, before the
   composer animates in. On iOS it renders the key window
   (`drawHierarchy(afterScreenUpdates: false)`); on a Mac it caches the key
   window's content view. It covers the app's own windows only, so no
   screen-recording permission is needed.
2. **More screenshots:** the person can dismiss the sheet, go to another
   screen and shake again, and the draft keeps what's there. They can also
   add images from Photos or Files.
3. **Logs:**
   - from `OSLogStore(scope: .currentProcessIdentifier)`, the last 15
     minutes, the app's own subsystems only (newest kept);
   - put in the body, folded in a `<details>` block, since the attachment
     endpoint takes only images and video. The cap keeps the body under
     GitHub's 65,536-character limit.
4. **About the app and device,** as a small table in the body:
   - the app's name, bundle id, version and build;
   - the OS and its version, and the device model;
   - the locale, the time zone, and the time of the shake.
5. **Title** (required) and **description.**
6. **Preview** (section 6), then **Create Issue,** which shows the issue's
   link. If it fails, the draft is kept to retry.

## 4. Attachments: GitHub's own

The owner asked for the attachments the web UI makes, the
`github.com/user-attachments/assets/…` URLs, since they're what GitHub
renders inline. Findings (November 2026):

- **There's now a supported client for that endpoint.** Since GitHub CLI
  2.99.0 (changelog, 2026-09-01), `gh issue create --attach` is generally
  available. GitHub's docs cover it in "Attaching files with GitHub CLI".
- **The request (from `gh`'s source, `internal/attachments`):**

      POST https://uploads.github.com/user-attachments/assets
           ?name=<file>&content_type=<mime>&repository_id=<numeric id>
      Authorization: token <token>          (Bearer gets a 404)
      Content-Type: application/octet-stream
      Accept: application/vnd.github+json
      X-GitHub-Api-Version: 2022-11-28

  It returns `{"url": "https://github.com/user-attachments/assets/…"}`,
  which goes in the body as `![alt](url)`, as `gh` does. It's a plain token
  request, not the web UI's cookie and CSRF flow.
- **It isn't in the REST reference.** GitHub documents it only through
  `gh`, so it could change. `gh` is its main user, though, so it's unlikely
  to break quietly. If it changes, `GitHubIssues` is the one place to
  follow it.
- **Limits:**
  - types: PNG, JPEG, GIF, WebP, SVG, MP4, MOV and WebM;
  - sizes: 10 MB for an image; 10 MB for a video (100 MB on paid plans);
  - no GitHub Enterprise Server.
- **Which tokens it takes** (tested 2026-11-23):
  - The reporter needs write access to the repository; READ and TRIAGE
    get a 404.
  - OAuth App tokens (`gho_`, what `gh` uses) and personal access tokens
    are accepted.
  - A GitHub App's tokens are not: an installation token (`ghs_`) gets a
    404 even with Contents write, and so does a user token (`ghu_`) from
    the owner's own App.
  - GitHub's CLI maintainers confirm it: only first-party apps (such as
    Copilot's cloud agent) mint `ghu_` tokens the endpoint takes, and no
    setting enables it for anyone else's App (cli/cli#14495). The request
    to change that is cli/cli#14309.
- **Rendering and privacy:**
  - On a **private** repository, attachments uploaded against it need
    GitHub sign-in and access to that repository. They're served through
    short-lived signed URLs, so they render inline for the app's
    collaborators and for no one else.
  - On a **public** repository, attachments are public, like the issue.
    The composer says so before sending.
- **Rejected:**
  - files kept in a separate repository and linked from the issue: images
    from a private repository don't render inline in issues, even for
    viewers with access;
  - giving a GitHub App Contents permission: it doesn't open the endpoint;
  - the web UI's cookie upload flow: undocumented, and it needs a browser
    session.

So: **an OAuth App, its token uploading to user-attachments against the
app's own repository.** If an upload still fails, the issue is filed
without that attachment, with a note saying so. Every reporter needs write
access to the app's repository; that's the owner and the app's
collaborators, which fits who reports bugs.

## 5. Sign-in (`GitHubAuth`)

Device flow, with the owner's OAuth App, so the issue is opened as the
person who signs in. The person acts with their own access, under the
scope the app asks for.

- **Scope, per app:** `public_repo` when the app's issue repository is
  public, `repo` only when it's private (which reaches every repository the
  person can). It's a setting in each app (`ShakeKitScope`), stamped like the
  client id.
- **The sign-in screen:** it shows the code and "Open
  github.com/login/device", and polls until the person has entered the
  code.
- **Tokens:**
  - An OAuth App's token doesn't expire and has no refresh token.
    `GitHubAuth` also keeps handling expiring tokens and their refresh, for
    the switch to a GitHub App.
  - The token goes in the app's keychain, in the host app's own access
    group. It must never be a group shared with another app's GitHub
    sign-in, or one sign-in would replace the other.
  - It's keyed by the client id, and never printed or logged.
- **Sign Out** deletes the token from the keychain. Revoking it on GitHub
  needs the OAuth App's client secret, which never ships in an app, so the
  sheet says where to revoke it: GitHub › Settings › Applications.
- **Names and behaviour** follow the owner's existing GitHub client, so the
  two can merge:
  - `GitHubDeviceFlow`: takes a scope, honours `interval` and `slow_down`,
    and refreshes with `grant_type=refresh_token` when there's a refresh
    token;
  - `GitHubToken`, with optional expiry;
  - `TokenStore`, with `KeychainTokenStore` and `MemoryTokenStore`;
  - `GitHubCredentials`: renews before expiry when it can, and forgets the
    token on a 401.

  The owner's issues browser can move onto `GitHubAuth` and
  `GitHubIssues` once they're released.

**What the owner creates:** an **OAuth App** (Settings › Developer
settings › OAuth Apps), with this repository as its homepage and callback
URL (device flow never uses the callback), and **Enable Device Flow** on.
No client secret is generated or needed. Its client id (not a secret) goes
in each app's Info.plist as `ShakeKitClientID`, and the scope as
`ShakeKitScope`, both stamped by the app's CI.

## 6. Privacy

- **Logs:**
  - Only the app's own subsystems, from the last 15 minutes.
  - `.private` values arrive redacted already, as OSLogStore gives them.
  - Before upload, the composer also redacts tokens, email addresses and
    URL query strings.
  - An app can add its own rules.
- **Preview:**
  - The person sees every attachment and the full log text, and can
    remove any of them.
  - On a public repository the composer says "This issue and its
    attachments will be public." On a private one, it says who can see
    them.
- **No network until the composer opens:** no analytics and no crash
  hooks. Screenshots and logs stay in memory (or the app's container, for
  a kept draft), and are dropped once the issue is created.
- **Release builds:** with no `ShakeKitClientID`, ShakeKit does nothing.

## 7. Packaging and conventions (as update_kit)

- **One package, two ways in:**
  - a Swift package and a Bazel module in the same repository;
  - apps pin it `exact:` through SwiftPM or rules_swift_package_manager, or
    through the owner's bazel_registry.
- **Linux:** `swift test` runs on Linux, with GitHub's answers faked.
  Apple's frameworks sit behind one small platform protocol.
- **CI:**
  - on GitHub's hosted runners and cache (the repository is public);
  - Linux tests on every pull request;
  - an iOS and macOS build only when a release is verified;
  - release secrets, if any, in an environment limited to `v*` tags.
- **Proof:** every release carries one (format 2), with the tests' results
  and the composer on iOS (portrait and landscape) and macOS. The shots
  come from fixtures, with a fixed date, locale and appearance.
- **Tools and workflow files:** tools are in Swift. Workflow files are
  committed for agents by the repository's maintainer.
- **Versions** are tags the owner makes.
- **Process:**
  - a `changes/<branch>.md` fragment in each pull request;
  - one release per minor line;
  - a scoped CODEOWNERS.

## 8. Rollout

1. **The Shake App:** the owner creates it.
2. **The first spike:** check that its `ghu_` token can upload. If not,
   switch it to an OAuth App (section 4).
3. **0.1.0:** with `GitHubAuth`, `GitHubIssues`, `IssueComposer` and
   `ShakeKit`, on iOS and macOS.
4. **Each app:** its owner integrates it in a pull request of their own,
   with:
   - the modifier, and the commands on a Mac;
   - the client id in Info.plist;
   - the Shake App installed on its repository.

   The list of apps is kept with the owner, since some are private. The
   public ones: Visor, Playground and Isomer's Storybook.
5. **The issues browser** moves onto `GitHubAuth`, `GitHubIssues` and
   `IssueComposer` after 0.1.0 is tagged, in step with its owner, pinning
   it through rules_swift_package_manager.

The issues get a `shake-report` label, made on first use if missing.
