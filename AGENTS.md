# Repository Working Agreement

This file defines the default working rules for projects created from this repository. A project may contain a PHP web application, an iOS application, a watchOS application, a macOS application, or a deliberate combination of these targets.

Apply the general rules to every project. Apply a platform-specific section only when that platform is present. When an existing project already uses a clear, working convention, preserve it unless the user explicitly requests a migration or the convention conflicts with this file.

## 1. Goal and audience

Every repository must be professional, complete, secure, maintainable, and usable from a fresh clone of `main`.

Assume that the repository owner and many readers are beginning developers. Do not expect them to know specialist terminology or infer missing steps.

For every change:

- explain what changed and why in clear English;
- give copy-and-pasteable commands for setup, configuration, testing, and deployment where commands are needed;
- define unavoidable technical terms when first used;
- include concrete examples of expected input, output, and user-visible behaviour where useful;
- prefer explicit, readable implementations over clever abstractions;
- keep error messages actionable and safe to share;
- leave the project in a working state.

Do not claim that work is complete when required files, documentation, tests, configuration examples, or deployment instructions are missing.

## 2. Language and writing conventions

All source code, identifiers, code comments, developer-facing messages, commit messages, Pull Request text, and primary documentation must be written in English. User-facing text must be localized as described in section 7.

Write comments to explain intent, constraints, or non-obvious decisions. Do not comment on syntax that is already clear from the code.

Use Markdown for repository documentation. Keep headings descriptive, examples current, and links relative when they point to files in the same repository.

## 3. Repository structure

### 3.1 Required root files and directories

Every project must use this core structure:

```text
project/
├── .sync/          Reserved synchronization tooling; do not inspect or modify yet
├── .temporary/     Repository-local temporary and generated working files
├── docs/           Documentation, screenshots, and documentation artwork
├── .gitignore
├── AGENTS.md
└── README.md
```

Rules for the required directories:

- Put supplementary Markdown documentation in `docs/`.
- Put documentation screenshots in `docs/screenshots/`.
- Put icons for README and documentation in `docs/icons/`.
- Keep runtime assets with the application that uses them. For example, an iOS AppIcon belongs in its Xcode asset catalog, not in `docs/icons/`.
- Put all agent-created scratch files, local build output, rendered previews, and other disposable repository work in `.temporary/`.
- Ignore the contents of `.temporary/` in Git. A `.gitkeep` file may be committed so the directory exists in a fresh clone.
- Ignore the contents of `.sync/` in Git. Do not inspect, modify, delete, execute, or derive project rules from its contents unless the user explicitly asks for work on `.sync/`.

Application runtime temporary data may use the secure temporary or cache location provided by its platform. Do not make production code depend on development files in `.temporary/`.

### 3.2 Optional project directories

Create only the directories the project actually needs:

```text
project/
├── web/            PHP web application and browser assets
├── ios/            iOS application or iOS-specific target
├── watchos/        watchOS application or watchOS-specific target
├── macos/          macOS application or macOS-specific target
├── shared/         Code or assets genuinely shared by multiple platforms
├── scripts/        Optional local development and maintenance tools
├── examples/       Safe example input or sample data
└── tests/          Cross-project tests when they do not belong beside a target
```

- Do not add empty platform directories for platforms the project does not support.
- Follow the normal internal layout of each platform and its build tools.
- Keep platform-specific source, tests, configuration, and runtime assets inside that platform's directory.
- Use `shared/` only when at least two targets use the same code or asset. Do not move code there merely because it might be shared later.
- Keep target-specific tests beside or inside their target when that is the platform convention. Use the root `tests/` directory only for repository-wide or cross-platform tests.
- Keep optional Python and shell tooling in `scripts/`. Production application requests must never depend on a local maintenance script.
- Store script logs in `.temporary/logs/`, not in a tracked source directory.
- Existing repositories do not need to be reorganized solely to match this layout when moving files would add risk without a practical benefit. Document intentional differences in the README.

## 4. General implementation rules

### 4.1 Simplicity and dependencies

- Prefer platform standard libraries and built-in capabilities.
- Add an external package, framework, hosted service, or command-line dependency only when it has a clear benefit that would be expensive or unsafe to reproduce locally.
- Before adding a dependency, consider maintenance status, licensing, security, privacy, package size, platform support, and whether the project becomes unusable when the dependency is unavailable.
- Pin dependencies where the ecosystem supports it and commit required dependency manifests and lock files.
- Document every external dependency in the README, including why it is used, how it is installed, and any account, cost, privacy, or network requirement.
- Do not introduce broad frameworks or perform sweeping refactors unless the requested work needs them.
- Do not introduce a breaking change without documenting what breaks and how an existing user migrates.

### 4.2 Configuration and secrets

Use the configuration mechanism that fits the platform. Examples include:

- `config.php` with a committed `config.example.php` for a PHP application;
- a private `.xcconfig` with a safe committed example for an Apple application;
- a private `.env` with a committed `.env.example` only when the selected tooling genuinely uses environment files.

For every configuration format:

- commit a safe example containing labelled placeholders and non-secret sample values;
- ignore the real local or production configuration file;
- validate required values at startup or before deployment;
- fail with a clear, beginner-friendly message when configuration is missing or invalid;
- never commit, print, log, embed, or expose credentials, tokens, private keys, signing material, or production secrets;
- document exactly how to create the real configuration from its example;
- show the reader how to verify with `git status` that the private file is not tracked.

Do not make a fresh clone depend on an uncommitted file unless the README explains how to create it from a committed safe example.

### 4.3 Security and data handling

- Treat input from users, files, URLs, APIs, web views, devices, and inter-process messages as untrusted.
- Validate types, required fields, formats, ranges, allowed values, file sizes, and payload sizes at the boundary.
- Escape untrusted output for the context in which it is rendered.
- Use allowlists when the valid set of values is known.
- Store the minimum personal or sensitive data needed for the feature.
- Do not include secrets or personal data in logs, screenshots, fixtures, examples, or error messages.
- Use secure platform storage for credentials and sensitive tokens when they must be stored on a device.
- Keep sample data fictional and safe to publish, even when the repository is currently private.
- Review new dependencies and network calls for security and privacy implications.

### 4.4 Errors and logging

- Handle expected failure states explicitly.
- Show users a concise message that explains what they can do next.
- Log enough technical context to diagnose failures during development without logging secrets or unnecessary personal data.
- Make verbose or debug logging disable-able for production builds.
- Do not display stack traces, raw database errors, private paths, or internal credentials to end users.
- Include timestamps and relevant source context in persistent diagnostic logs.
- Write local development logs to `.temporary/logs/` unless a platform-standard diagnostic system is more appropriate.

### 4.5 User interface and accessibility

Every user interface must support both light and dark appearance.

- Follow the operating system or browser preference by default.
- Use semantic or design-token colours so both appearances remain consistent.
- Check text, controls, borders, focus states, charts, images, and disabled states in both appearances.
- Maintain readable contrast and do not communicate meaning through colour alone.
- Support keyboard navigation, visible focus, meaningful labels, scalable text, and assistive technology where the platform supports them.
- Respect reduced-motion and similar accessibility preferences when animation is present.

## 5. Internet access
Internet access may be used for technical research and documentation.
- Prefer primary and official documentation.
- For Apple development, prefer developer.apple.com and swift.org.
- For PHP, prefer php.net.
- For WordPress, prefer developer.wordpress.org.
- Never include source code, credentials, API keys, private project data, file contents, personal information or secrets in web searches.
- Never upload project files to external services.
- Use web search to find information, not to share project context.

## 6. README requirements

Every repository must contain a complete `README.md` in English. It must allow a beginning developer to understand, install, configure, use, test, build, and deploy the project without relying on undocumented knowledge.

Include the following sections when applicable:

1. Project name and a one-sentence description.
2. Current status, including material limitations or unfinished areas.
3. Features and supported platforms.
4. Screenshots or a short visual demonstration, stored under `docs/`.
5. Supported languages.
6. Requirements, including supported operating systems, runtime versions, tools, accounts, and hardware.
7. Installation with commands that can be copied exactly.
8. Configuration, including how to copy each safe example and where to enter values.
9. Usage with at least one concrete example.
10. Development setup and relevant project structure.
11. Tests, linting, type checks, builds, and how to interpret common failures.
12. Deployment or distribution, including shared-hosting steps, TestFlight, App Store, notarization, or other relevant channels.
13. External dependencies and why they are required.
14. Troubleshooting for likely beginner mistakes.
15. Known limitations and compatibility notes.
16. Contributing guidance when contributions are accepted.
17. License and third-party attribution.

Do not leave empty template headings or placeholder text in a finished README. Omit a section only when it genuinely does not apply. Keep README commands and screenshots synchronized with the current implementation.

Supplementary documentation belongs in `docs/`, but the README must link to it and remain sufficient as the starting point.

## 7. Gitignore and repository hygiene

The root `.gitignore` must be reviewed whenever the project gains a platform, tool, generated artifact, secret format, local database, or upload location.

Ignore, where applicable:

- `.temporary/` contents except an optional `.gitkeep`;
- operating-system metadata such as `.DS_Store` and `Thumbs.db`;
- editor and IDE user state;
- build products, derived data, caches, coverage, logs, and test results;
- downloaded dependencies such as `vendor/` and `node_modules/`;
- real configuration and secret files;
- credentials, signing keys, provisioning material, and private certificates;
- local databases, uploads, and user-generated data;
- local server state and machine-specific paths.

Do not ignore files required to build, test, or run a fresh clone. Commit, where applicable:

- source code and runtime assets;
- dependency manifests and lock files;
- database migrations and schemas;
- Xcode project or workspace configuration required by other developers;
- build and deployment configuration that contains no secrets;
- safe configuration examples;
- required scripts, fixtures, examples, documentation, screenshots, and license notices.

Avoid unnecessarily broad patterns such as ignoring every file with a common source or configuration extension. Before completing work, use `git status` and the relevant Git ignore diagnostics to confirm that required files are tracked and private files are ignored.

## 8. Localization

All projects with user-facing text must ship complete translations for these locales:

| Language | Locale identifier |
| --- | --- |
| English | `en` |
| Dutch | `nl` |
| French | `fr` |
| German | `de` |
| Spanish | `es` |
| Italian | `it` |
| Portuguese (Brazil) | `pt-BR` |

Localization behaviour must follow these rules:

- Use the operating-system or browser language on first launch.
- Provide a manual language choice when the application has persistent settings or when changing the system language would be unreasonable.
- Persist the manual choice and make it possible to return to automatic system-language selection.
- Fall back to English when a locale or translation is unavailable.
- Keep user-facing strings out of source code when the platform provides string catalogs or locale files.
- Do not construct sentences by concatenating translated fragments.
- Use locale-aware formatting for dates, times, numbers, currencies, units, plural forms, and names.
- Verify that every required locale has the same keys and compatible placeholders.
- Check layouts with long translations and large text sizes.
- Do not call a localization complete while visible source-language text or missing translation keys remain.

Every project must also be technically ready for Japanese (`ja`), Korean (`ko`), and Simplified Chinese (`zh-Hans`), even when those translations are not yet included. This means using Unicode throughout, externalized strings, adaptable layouts, locale-aware formatters, and no assumptions that text uses Latin characters or spaces. These three translations become required only when the project explicitly adds support for them.

## 9. Web projects

These rules apply when `web/` is present.

### 9.1 Runtime and language boundaries

- The production runtime must use PHP 8.3 or later, HTML, CSS, and vanilla JavaScript.
- Add `declare(strict_types=1);` to every PHP source file.
- Follow PSR-12 formatting and PSR-4 when autoloading is used.
- Prefer small procedural functions. Introduce classes only when state or complexity clearly warrants them.
- Use `snake_case` for PHP functions and variables.
- Render useful HTML on the server first and add JavaScript as progressive enhancement.
- Use the CSS `prefers-color-scheme` media feature for the default light or dark appearance. A manual theme choice may override it when the application provides appearance settings.
- Do not use React.
- Python may be used only for optional local tooling in `scripts/`; production web requests must not depend on Python or shell commands.
- Keep PHP application code, browser assets, data, uploads, and API endpoints in clearly named subdirectories under `web/`.

### 9.2 URLs and API responses

- Public page and API URLs must not expose the `.php` extension.
- Generate only canonical extensionless links, such as `/about` and `/api/status`.
- Redirect direct `.php` requests to the canonical clean URL when feasible.
- Implement routing with Apache rewrites, a front controller, or another shared-hosting-compatible approach.
- Return API responses as JSON with correct status codes and content-type headers.
- Use a consistent error structure such as `{ "error": { "code": "invalid_input", "message": "The supplied value is invalid." } }`.
- Keep endpoint flow explicit: parse and validate input, call business logic, then build the response.
- Version contracts that cross an app bridge or may evolve incompatibly.

### 9.3 PHP and browser security

- Escape user-generated HTML by default. If limited HTML is required, use and document an allowlist sanitizer for permitted tags and attributes.
- Use prepared statements for every database query containing variable data.
- Validate `$_GET`, `$_POST`, `$_FILES`, cookies, headers, and JSON bodies before use.
- For uploads, allowlist MIME types and extensions, enforce size limits, generate random server-side filenames, and never trust a user-provided filename.
- Store uploads outside the public document root when hosting permits it.
- Store SQLite databases under `web/data/database/`, never under uploads or the public asset tree.
- Do not expose production errors or stack traces in HTTP responses.

### 9.4 Shared-hosting target

Web projects must work within this deployment environment:

- PHP `8.3.29`, running through FPM/FastCGI;
- Apache 2 with HTTP/2;
- Linux with default timezone `Europe/Amsterdam`;
- `memory_limit`: `512M`;
- `max_execution_time`: `300` seconds;
- `post_max_size`: `64M`;
- `upload_max_filesize`: `64M`;
- `max_file_uploads`: `20`;
- `open_basedir` enabled.

Do not rely on `exec`, `system`, `passthru`, `shell_exec`, `proc_open`, `proc_close`, `popen`, `dl`, or restricted `posix_*` functions.

Use only project-controlled writable paths under `web/data/` and `web/uploads/`. Use `sys_get_temp_dir()` for short-lived production temporary files when appropriate and permitted by the host.

Available capabilities include PDO with MySQL and SQLite drivers, Redis, Imagick, and GD. Do not adopt Redis unless the project explicitly needs it.

Image constraints:

- accept JPEG, PNG, or WebP when server-side decoding is required;
- GD supports JPEG, PNG, and WebP but not AVIF;
- Imagick is available but cannot decode HEIC or HEIF on this host;
- do not implement production image work by shelling out to ImageMagick or FFmpeg.

### 9.5 Web verification

Run configured PHP and frontend checks when present, including PHPUnit, PHPStan, PHP style checks, JavaScript tests, and linters.

Every web feature and bug fix must also be verified through the affected user flow in a real Chromium browser, preferably with Playwright. Code-level tests alone are insufficient.

Use this loop until the flow passes or a concrete blocker remains:

1. Reproduce or exercise the relevant flow.
2. Record the actual result and browser errors.
3. Fix problems caused by the current work.
4. Repeat the browser test.

Do not state that a web feature works or a web bug is fixed until Chromium verification passes. If browser verification is impossible, state precisely what remains unverified and why.

## 10. Apple platform projects

These general Apple rules apply when `ios/`, `watchos/`, or `macos/` is present.

- Use Swift for new source code unless an existing target already requires Objective-C.
- Prefer SwiftUI for new interfaces. Use UIKit, WatchKit, or AppKit when an existing architecture or required platform capability makes it the clearer choice.
- Prefer Apple frameworks and small, testable components over third-party abstractions.
- Keep each target's capabilities, entitlements, assets, configuration, and tests with that target.
- Put code in `shared/` only when multiple targets compile or consume it. Keep platform adapters separate from shared business logic.
- Declare supported operating-system and Xcode versions in the README.
- Keep bundle identifiers, app groups, URL schemes, capabilities, and target relationships documented in one discoverable place.
- Validate data received from URLs, share extensions, notifications, connectivity sessions, web views, and other processes.
- Never hardcode backend secrets, API keys, credentials, certificates, or provisioning profiles in source code.
- Use platform-provided secure storage for sensitive device data.
- Use string catalogs or the current Apple localization mechanism for user-facing text.
- Use semantic system colours and verify every screen in light and dark appearance.
- Support Dynamic Type where the platform provides it, VoiceOver labels, logical focus order, and appropriate input methods.
- Commit Xcode project, workspace, scheme, package manifest, and resolved dependency files required for a fresh clone to build.
- Do not commit personal signing data, user-specific Xcode state, DerivedData, archives, or exported credentials.
- Explain automatic or manual signing, required capabilities, test devices, distribution, and any Apple Developer account requirement in the README.

### 10.1 iOS

- Keep the iOS application and iOS-only extensions under `ios/`.
- Keep share extensions, widgets, notification extensions, and other targets small and explicit.
- If the app embeds web content, isolate `WKWebView` setup, message handlers, and native feature adapters.
- Allowlist bridge message names and validate every bridge payload.
- Restrict web-view navigation to trusted schemes and domains where feasible.
- Require explicit user intent before a web bridge invokes a privileged native action.
- The web application must remain usable in a normal browser when an iOS bridge is optional.

### 10.2 watchOS

- Keep the watch experience focused on short, glanceable interactions.
- Do not assume that the paired iPhone is always reachable.
- Define and test offline, delayed-sync, duplicate-message, and reconnect behaviour.
- Minimize background work, network use, memory use, and battery impact.
- Keep WatchConnectivity payloads small, versioned when necessary, and validated on receipt.
- Document whether the watch app is independent or requires its companion iOS app.

### 10.3 macOS

- Use standard macOS window, menu, keyboard, focus, drag-and-drop, and file-access conventions.
- Explain sandboxing, entitlements, file permissions, login items, helper tools, and accessibility permissions when the project uses them.
- Store user data in appropriate macOS application support locations rather than inside the application bundle.
- Document signing, hardened runtime, notarization, packaging, and distribution steps when the app is distributed outside local development.
- For every macOS build shared outside the development machine, use the repository's `macos-direct-distribution` skill. Never share a loose or unnotarized `.app`; distribute a signed, notarized, and stapled DMG containing the app and an Applications shortcut.
- For directly distributed macOS apps, keep the README limited to project-specific DMG installation instructions, stable and beta appcast URLs, the selected update channel, the exact skill command, the upload destination, and a rollback procedure. Do not duplicate the generic signing, notarization, DMG, or Sparkle workflow from the skill.

### 10.4 Apple builds and tests

For every affected Apple target:

- run the configured unit and user-interface tests;
- run an `xcodebuild` build for the relevant scheme and destination;
- run SwiftLint or other configured static checks when present;
- test localization, light and dark appearance, accessibility text sizes, and important failure states;
- verify cross-target behaviour on both sides when changing shared code, app groups, extensions, or device communication.

Record the exact schemes, destinations, and commands in the README. If signing, unavailable hardware, simulator limitations, or external services prevent a check, report the exact limitation and do not describe the result as fully verified.

## 11. Definition of done

Before describing any task as complete:

1. Review the complete change, including untracked files.
2. Confirm that the implementation matches the user's request without unrelated refactoring.
3. Confirm that no secret, private data, cache, temporary artifact, local database, upload, or machine-specific setting is included.
4. Confirm that every required source file, asset, manifest, lock file, migration, schema, script, and configuration example is tracked.
5. Run the relevant tests, linting, type checks, builds, and platform verification.
6. Fix failures caused by the current work and repeat the affected checks.
7. Update the README and `docs/` when behaviour, setup, configuration, supported platforms, localization, dependencies, or deployment changed.
8. Check the affected interface in light and dark appearance and in every required language.
9. State any unverified behaviour or remaining limitation precisely.

## 12. Git and Pull Request workflow

`main` is the canonical, complete, and distributable version of the project. A fresh clone or download of `main` must contain everything required to build and run the project according to the README. The project must never depend on uncommitted or purely local files.

### 12.1 Normal development

Do not make unfinished changes directly on `main`.

If currently on `main`, create a descriptive task branch before making changes. Use an appropriate prefix:

- `feature/` for new user-visible behaviour;
- `bugfix/` for a defect correction;
- `docs/` for documentation-only work;
- `chore/` for maintenance that does not change product behaviour.

If already working on a non-`main` task branch or in an isolated worktree, continue using it instead of creating a nested or duplicate branch.

Before considering local work complete:

1. Review all changes with `git status` and `git diff`.
2. Make sure every file required by the change is tracked.
3. Keep unrelated pre-existing changes out of the task.
4. Run the appropriate tests, linting, type checks, build checks, and platform verification.
5. Fix failures caused by the current work.
6. Update documentation when behaviour, installation, configuration, dependencies, or deployment changed.

Do not commit, push, create a Pull Request, or merge merely because implementation work is complete. Those actions require the exact `ship` command described below or another explicit user instruction that clearly requests a narrower Git action.

### 12.2 The exact `ship` command

When the user's entire message is exactly:

```text
ship
```

treat it as an instruction to complete the entire Git and GitHub delivery workflow autonomously.

Perform this process:

1. Inspect the working tree and confirm that the current implementation is complete.
2. Check for missing required files, accidentally untracked files, private files, temporary artifacts, and incomplete changes.
3. Fetch the latest `origin/main`.
4. Bring the task branch up to date with `origin/main` and resolve conflicts when necessary.
5. Commit all changes belonging to the completed task with a clear, beginner-friendly commit message.
6. Push the task branch to `origin`.
7. Create a GitHub Pull Request targeting `main`.
8. Give the Pull Request a concise descriptive title, a summary of the completed change, important implementation details, user-visible effects, and the tests and checks performed.
9. Check the Pull Request's merge status and required reviews.
10. Once the Pull Request is valid and mergeable, merge it into `main`, preferably with squash merge unless the repository requires another strategy.
11. Delete the remote task branch after a successful merge when repository policy permits it.
12. Update local `main` from `origin/main` when the environment permits it, then delete the merged local task branch when safe.
13. Verify that `origin/main` contains the merged work.
14. Verify that the resulting repository is clean and that no required project file exists only locally.

The `ship` workflow is finished only when the completed change exists on `origin/main`.

If GitHub permissions, branch protection, required human review, authentication, signing access, unavailable hardware, or another external restriction prevents completion, do not bypass it. Complete every safe step that is possible and report the exact remaining blocker.

If there are no actual changes to ship, do not create an empty commit or artificial Pull Request.

Never force-push `main`.
