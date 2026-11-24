# Crashes (ShireworksCrashes)

The app's crashes, caught on the device and filed as GitHub issues in its
repository: one issue a crash, commented on each time it happens again, and
opened again when a fix didn't hold.

    import ShireworksCrashes   // or ShireworksKit

    // At launch, once (in the App's init, say):
    ShireworksCrashes.start()

The repository is the Info.plist's `ShireworksRepository` ("owner/name"),
stamped in by the distributor's CI, or given in code
(`CrashesConfiguration(repository:)`). It files with the shared sign-in
(`GitHubSharedSignIn`, as Shake does): the build needs its Info.plist keys
and entitlements.

## How it works

1. **Caught.** On iOS and macOS a crash reporter catches the crash as it
   happens and writes it down; the process ends as it would have.
2. **Handed over.** At the next launch, `start` starts the reporter again,
   which reads the last run's crash and hands it over. Crashes reads it into
   a `CrashReport`: the app's version and build, the system and the device
   model, the exception (its type, its reason, how it was caught), the
   crashing thread's frames, the other threads, the binary images loaded,
   and the breadcrumbs left before it.
3. **Kept.** The report goes into the app's `CrashStore`, a folder of JSON
   files (`Application Support/ShireworksCrashes/<bundle id>`): at most the
   newest 20 (`maxStored`), for at most 30 days (`maxAge`).
4. **Filed.** In a background task, each kept report is filed with the
   shared sign-in (`CrashFiler`) and, once filed, let go.

## The crash reporter: Sentry's SDK, on the device alone

The reporter is [sentry-cocoa](https://github.com/getsentry/sentry-cocoa)
(9.35.0, built from source, `SentrySPM`), an implementation detail: none
of its types is in the API, and all of it is in one file
(`Sources/ShireworksCrashes/Platform.swift`). There is no Sentry account and
no Sentry project:

- It is started with a DSN that names no project, at a host that doesn't
  exist (`o0.ingest.invalid`).
- Its `beforeSend` drops every event, a crash's (level `fatal`) handed to
  Crashes first: nothing is ever sent.
- Everything but its crash handler is off: app hang and watchdog
  termination tracking, sessions, tracing and performance, network, file
  and Core Data tracking, failed requests, swizzling, MetricKit, metrics,
  logs, client reports, screenshots, view hierarchies and session replay;
  `sendDefaultPii` is false.
- Its files are in the app's caches (`Caches/ShireworksCrashes/<bundle id>`).

Elsewhere (Linux, Isomer's hosts) there is no reporter for now: `start`
does nothing and says so (false). The rest (the report, the store, the
filer) is the same everywhere, and tested on Linux and on a Mac.

## One issue a crash

A crash's **signature** is the exception's type and its top three frames of
the app's own (the top three frames where none is the app's), each by its
symbol, or by its image and its offset in it where the device had none:
hashed with 64-bit FNV-1a, 16 hex digits. Not the reason, whose addresses
change from run to run.

Its issue's body ends with two HTML comments, unseen on GitHub:

    <!-- shireworks-crash: <signature> -->
    <!-- shireworks-crash-version: <the newest version it was seen in> -->

The filer looks the signature up with GitHub's search
(`repo:owner/name is:issue in:body "shireworks-crash: <signature>"`, the
marker then matched exactly in each body found): one request however many
crash issues there are, open or closed, labelled or not. The issues it
opened in this run it remembers, as the search trails a new issue by a
little.

- **None:** an issue opens, titled
  `Crash: <type>: <short reason> (<top frame of the app's>)`, labelled
  `crash`, with the summary, the crashing thread in a code block, the app
  and device in a table, the other threads, binary images and breadcrumbs
  folded in `<details>`, and the markers. It is kept under 60,000 bytes
  (GitHub takes 65,536 characters): the folded parts are cut first, the
  largest first, then the crashing thread's outermost frames.
- **Open:** a comment, "Again in <version> (<build>), <device>, <system>,
  <date>", with the crashing thread.
- **Closed:** the comment too; and if the crash comes from a version newer
  than any it was seen in (the version marker, compared part by part as
  numbers), the fix didn't hold: it opens again. A crash from that version
  or an older one (a build still in someone's hands) only comments.

Each newer version seen is written into the version marker.

## Privacy

Before anything is filed it is redacted: GitHubIssues' `IssueRedaction`
(tokens, email addresses, a URL's query), the name of a home folder in a
path (`/Users/<redacted>/…`, `/home/<redacted>/…`), and the host's own
patterns (`CrashesConfiguration.redactions`). Images are named by their file
name alone, never their path. The reporter collects no personal data
(`sendDefaultPii` off, no screenshots, no view hierarchy), and sends nothing
anywhere: the only thing that leaves the device is the issue, filed as the
signed-in user.

## No sign-in

Crashes has no sign-in of its own. On a device where nobody is signed in to
the shared sign-in (or the build carries none, or names no repository),
nothing is filed and the crashes stay kept, bounded and pruned, until
someone signs in or they're pruned. A sign-in GitHub refuses (a 401) is let
go, as Shake does, and the crashes stay kept; so do they when GitHub can't
be reached, or refuses the repository (403, 404). A crash GitHub refuses on
its own (a 422) stays kept, and the next one is filed.

## Symbolication: not yet

A device rarely has symbols for the app's own code, so frames are mostly
named by their image and offset (`MyApp + 0x1a2b`), and the binary images
by their UUID and load address: what symbolicating them against the build's
dSYMs takes (`atos -o MyApp.dSYM/... -l <load address> <address>`). That is
left for later (CI keeping each build's dSYMs, and a step that symbolicates
an issue's frames). Until then a crash in code without symbols has a
signature per build, since its offsets move from build to build.
