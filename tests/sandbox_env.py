"""Environment for running the real scripts with a throwaway HOME."""

import os

# Besides HOME, the variables that relocate where the scripts read or write
# (the systemd user unit dir follows XDG_CONFIG_HOME before HOME/.config). A
# desktop session sets it, so tests running directly on such a host would
# otherwise write into the real user's systemd units.
HOST_PATH_VARIABLES = ("XDG_CONFIG_HOME",)


def sandboxed_environ(home, dropped=()):
    """A copy of os.environ with HOME set to home and every variable that could
    point the scripts at the real user's files removed, plus the DROPPED ones."""
    excluded = HOST_PATH_VARIABLES + tuple(dropped)
    environ = {key: value for key, value in os.environ.items() if key not in excluded}
    environ["HOME"] = home
    return environ
