# NEXUS Terminal: Ubuntu Bash integration

## Current status

The browser desktop contains a **Terminal preview**, not a shell. It does not launch processes, read the host filesystem, or execute commands. Submitting text in preview mode only reports that the native Bash backend is unavailable. This is intentional: browser JavaScript cannot provide a genuine Ubuntu shell.

GNU Bash is the target interactive shell for the native NEXUS system. Utilities such as ls, grep, find, apt, and sudo are separate Ubuntu executables, not Bash built-ins.

## Native architecture target

The native implementation should keep the UI separate from a privileged, narrowly scoped terminal-session service:

1. The NEXUS UI requests a terminal session from a trusted native service.
2. The service starts an interactive Bash process attached to a PTY (pseudo-terminal), using the logged-in desktop user's identity and normal permissions.
3. The service streams PTY output to the UI and forwards input, resize, interrupt, and close events.
4. Session teardown closes the PTY and terminates the child process reliably.

The initial shell should be the system Bash executable (normally /bin/bash) in interactive mode. The native service should define a controlled working directory and a documented environment. It must not run Bash as root, silently elevate privileges, or expose a general-purpose host command API to web content.

## Security requirements

- The native service must be part of the trusted NEXUS desktop/runtime, not an API exposed to arbitrary websites.
- Authenticate and authorize every session request against the active desktop user.
- Keep each PTY attached to that user's permissions and filesystem access.
- Do not pass commands through JavaScript eval(), construct shell commands from UI strings, or use a browser-side command interpreter.
- Do not offer a browser-originated arbitrary process-spawn endpoint.
- Apply session limits, clean up abandoned sessions, and close PTYs when the app exits.
- Preserve normal Ubuntu permissions and sudo policy; do not make the shell privileged by default.
- Treat terminal output as text, not trusted HTML.

## Native terminal service contract to implement

The UI/backend boundary should expose session-oriented operations rather than a generic execute-command method:

- openSession({ cols, rows }) — create an authenticated interactive Bash/PTY session.
- write(sessionId, data) — write terminal input to that session's PTY.
- resize(sessionId, cols, rows) — resize the PTY.
- interrupt(sessionId) — send the terminal interrupt signal to the foreground process group.
- closeSession(sessionId) — close the PTY and terminate/reap the child process.
- An output/event stream — deliver stdout/stderr bytes, exit status, and session errors.

This is an architectural contract, not an implemented backend. The browser preview must not attempt to emulate these operations.

## Compatibility and validation plan

A native integration is not complete until a real Ubuntu GNU Bash process is launched and tested. Validate at least:

- Bash identity and version (bash --version, $BASH_VERSION).
- Built-ins, arguments, environment variables, working directory, and exit codes.
- Chaining, pipelines, quoting, globbing, and input/output redirection.
- History, interactive editing, tab completion, Ctrl+C, and Ctrl+L.
- Ubuntu utilities such as ls, grep, find, and apt where installed.
- PTY resize, process exit, disconnect, cancellation, and cleanup.
- Permission boundaries, non-root startup, and isolation from untrusted browser origins.

Until those checks run against the native service, describe the feature as **planned native Bash integration** rather than Bash-compatible or complete.
