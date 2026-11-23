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
  - **Drafts** are kept through a small protocol, `DraftStore`, which
    defaults to a JSON file in the app's container (`FileDraftStore`):
    screenshots are too big for `UserDefaults`.
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
  key window through the responder chain) opens the composer, **only for
  someone signed in** (through the apps' shared sign-in, or ShakeKit's
  own). Nobody else's shake does anything, so ShakeKit can be in every
  build without springing a sign-in on people. Shakes that come in while
  it's up are ignored.
- **macOS.** No shake: `ShakeKitCommands()` adds the menu command and its
  shortcut.
- **Other hosts:** later. The API is kept portable, so they can follow
  through Isomer.
- `ShakeReport.request()` opens it deliberately, for the app's own "Report
  a Bug" button; so does the Mac's menu command. A deliberate request opens
  it signed in or not, offering ShakeKit's own sign-in: that's how someone
  chooses to start it.
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
  - The owner's OAuth App has token expiration on: a token lasts 8 hours
    and comes with a refresh token (about 181 days), which `GitHubAuth`
    uses to renew it. Expiry stays optional, for an OAuth App without
    expiration.
  - Tested 2026-11-23: the refresh needs no client secret (`client_id`,
    `grant_type=refresh_token` and `refresh_token` alone). It rotates both
    tokens: the old access token is refused at once, so the renewed pair is
    kept before it's used.
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

**A sign-in the host's apps share.** Where the host carries one (the
`GitHubShared…` keys in its Info.plist, stamped by its CI, and the keychain
and app groups they name), ShakeKit files with it, so someone signed in to
one of the owner's apps needn't sign in again. That only happens when its
token covers ShakeKit's scope; otherwise ShakeKit uses its own sign-in.
ShakeKit never signs in to the shared one, or signs out of it: asking for a
narrower scope would replace the token the other apps rely on.

**The apps** (both named `logan-shire-shake`; tell them apart by client
id, which is public, not a secret):

| App | Client id | Used for |
| --- | --- | --- |
| OAuth App | `Ov23liV9P5ku0ntejoEc` | Sign-in today: device flow, attachments inline |
| GitHub App | `Iv23liWyhH9QbD6m7yx3` | Later, when GitHub lets App tokens upload attachments (TODO.md) |

The OAuth App has this repository as its homepage and callback URL (device
flow never uses the callback), **Enable Device Flow** on, and no client
secret. Its client id is ShakeKit's default `ShakeKitClientID`. An app can
override it, and sets its scope as `ShakeKitScope`, in its Info.plist, both
stamped by its CI.

Tested 2026-11-23: the OAuth App's `gho_` token, with scope `public_repo`,
uploaded to user-attachments against this repository (201) and got a
`github.com/user-attachments/assets/…` URL.

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
- **Every build:** in the owner's apps, CI stamps `ShakeKitScope` (or
  `ShakeKitClientID`) into every build, production included (the owner,
  2026-11-23). A build without either offers no report at all. In a build
  with it, a shake shows nothing to anyone who isn't signed in; reporting
  starts only when someone is signed in or asks for it themselves.

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

1. **The apps:** the owner created both (section 5). Done.
2. **The spike:** the GitHub App's `ghu_` token can't upload; the OAuth
   App's `gho_` token can (section 4). Done.
3. **0.1.0:** with `GitHubAuth`, `GitHubIssues`, `IssueComposer` and
   `ShakeKit`, on iOS and macOS.
4. **Each app:** its owner integrates it in a pull request of their own,
   with:
   - the modifier, and the commands on a Mac;
   - its scope in Info.plist (`ShakeKitScope`: `public_repo`, or `repo` for
     a private repository).

   An OAuth App isn't installed on repositories: the person's own access
   decides where they can file.

   The list of apps is kept with the owner, since some are private. The
   public ones: Visor, Playground and Isomer's Storybook.
5. **The issues browser** moves onto `GitHubAuth`, `GitHubIssues` and
   `IssueComposer` after 0.1.0 is tagged, in step with its owner, pinning
   it through rules_swift_package_manager.

The issues get a `shake-report` label, made on first use if missing.
