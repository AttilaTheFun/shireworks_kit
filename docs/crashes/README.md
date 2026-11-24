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

1. **Recorded.** On iOS and macOS a crash recorder catches the crash as it
   happens and writes it down, a JSON report in the app's caches; the
   process ends as it would have.
2. **Handed over.** At the next launch, `start` starts the recorder again
   and reads every report it kept (`CrashRecording`) into a `CrashReport`:
   the app's version and build, the system and the device model, the
   exception (its type, its reason, how it was caught), the crashing
   thread's frames, the other threads, and the binary images the frames
   are in. Each one kept is deleted from the recorder's own store.
3. **Kept.** The report goes into the app's `CrashStore`, a folder of JSON
   files (`Application Support/ShireworksCrashes/<bundle id>`): at most the
   newest 20 (`maxStored`), for at most 30 days (`maxAge`).
4. **Filed.** In a background task, each kept report is filed with the
   shared sign-in (`CrashFiler`) and, once filed, let go.

## The crash recorder: KSCrash, on the device alone

The recorder is [KSCrash](https://github.com/kstenerud/KSCrash) (2.6.1,
MIT, its `Recording` library built from source; what Sentry's own Apple SDK
records crashes with), an implementation detail: none of its types is in
the API, and all of it is in one file
(`Sources/ShireworksCrashes/Platform.swift`). It has no service and sends
nothing anywhere; there is no account of any kind.

- Its monitors are the crash ones only: Mach exceptions, signals, C++
  exceptions and uncaught NSExceptions. No hang, watchdog, main-thread
  deadlock, zombie or memory-termination monitors, no hang or CPU reports.
  (KSCrash always adds its few required ones, the system's and the app's
  state, which write no report of their own.)
- No memory introspection, no console log, no queue names in a report, and
  no rebinding of `__cxa_throw`.
- A report names only the binary images its frames are in.
- Its files are in the app's caches (`Caches/ShireworksCrashes/<bundle id>`).

Elsewhere (Linux, Isomer's hosts) there is no recorder for now: `start`
does nothing and says so (false). The rest (the report, the store, the
filer) is the same everywhere, and tested on Linux and on a Mac.

## One issue a crash

A crash's **signature** is the exception's type and its top three frames of
the app's own (the top three frames where none is the app's), each by its
symbol: hashed with 64-bit FNV-1a, 16 hex digits. Not the reason, whose
addresses change from run to run. Where a top frame has no symbol (a release
build's own code, mostly), an offset would move with every build, so the
signature is the exception's type, its reason with its numbers and
addresses taken out, and those frames by their image alone: the same crash
keeps one issue from build to build, at the cost of sometimes taking two
crashes in one image for one (each comment carries its own crashing
thread).

In a public repository the reason isn't filed (see Privacy), so there that
path leaves the reason out too: the exception's type and the frames alone,
so a crash is never found by text its issue doesn't carry. Where every top
frame has a symbol the two signatures are the same; where one hasn't, a
public repository's signature differs from a private one's, so a
repository that changes its visibility may get a new issue for a crash
already filed, once.

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
  `Crash: <type>: <short reason> (<top frame of the app's>)`
  (`Crash: <type> (<top frame of the app's>)` in a public repository), labelled
  `crash`, with the summary, the crashing thread in a code block, the app
  and device in a table, the other threads and binary images (and
  breadcrumbs, where a report has any; KSCrash's have none) folded in
  `<details>`, and the markers. It is kept under 60,000 bytes
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
name alone, never their path, and nothing of the recorder's system
details beyond the version, the system and the machine's model goes in. The
recorder reads no memory and no console, and sends nothing anywhere: the
only thing that leaves the device is the issue, filed as the signed-in
user.

### Public repositories

Redaction catches what looks like a secret, not what a person wrote: an
exception's reason ("Could not open \"Letter to a friend.txt\"") and the
breadcrumbs can carry the user's own words. A public repository's issues
are anyone's to read, so there they're left out:

- Each filing pass asks GitHub first whether the repository is private
  (`GET /repos/{owner}/{name}`, its `private`, with the same sign-in;
  `GitHubIssuesClient.isPrivate(repository:)`). Where GitHub says it
  isn't, or can't say (no network, a refusal other than a 401, an answer
  without it), it counts as public. A 401 is a refused sign-in, as for
  every other request: the crashes stay kept.
- In a public repository the title is the exception's type and the top
  frame (`Crash: EXC_BAD_ACCESS (MyApp + 0x1a2b)`); the body's summary says
  `(reason left out: public repository)` in place of the reason, and the
  breadcrumbs aren't there. The exception's type and how it was caught, the
  frames, the other threads, the binary images, and the app, system and
  device are, as in a private one's. The "Again in …" comments carry
  neither the reason nor the breadcrumbs anywhere.
- The signature there leaves the reason out (see "One issue a crash").

An app whose reasons and breadcrumbs carry nothing of the user's can file
them in a public repository too: `ShireworksCrashesPublicDetails` (a
Boolean, true) in its Info.plist, or `CrashesConfiguration(publicDetails:
true)`. Then the repository's visibility isn't asked.

## No sign-in

Crashes has no sign-in of its own. On a device where nobody is signed in to
the shared sign-in (or the build carries none, or names no repository),
nothing is filed and the crashes stay kept, bounded and pruned, until
someone signs in or they're pruned. A sign-in GitHub refuses (a 401) is let
go, as Shake does, and the crashes stay kept; so do they when GitHub can't
be reached, or refuses the repository (403, 404). A crash GitHub refuses on
its own (a 422) stays kept, and the next one is filed.

## Symbolication: on the device, as far as it goes

The recorder names each frame by the symbol the device has for it: the
system's libraries' always, and the app's own where its executable keeps
them (a debug build; a release build's exported ones). Where it has none,
or only the executable's header (`_mh_execute_header`, a stripped
executable's nearest), a frame is named by its image and offset
(`MyApp + 0x1a2b`), and the binary images by their UUID and load address:
what symbolicating them against the build's dSYMs takes
(`atos -o MyApp.dSYM/... -l <load address> <address>`). That is left for
later (CI keeping each build's dSYMs, and a step that symbolicates an
issue's frames). Swift's symbols are shown mangled (`$sSayxSicig`), as the
recorder writes them.
