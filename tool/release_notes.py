#!/usr/bin/env python3
"""Release notes for the fork's releases, written once in RELEASE_NOTES.md.

Changes for the next release go under "## New" in RELEASE_NOTES.md, and
only there. The release workflow uses this script to

  body <tag> <out> [--allow-empty]
      write the text of the GitHub release for <tag>: the notes with
      "## New" headed "## New in <version>". Fails when "## New" has no
      entry, unless --allow-empty (test builds).

  changelog <tag>
      before building: add the "## New" entries (plain text) to the
      CHANGELOG.md section of the app's base version, so the app built for
      <tag> shows them in its changelog. Only the build's working copy is
      changed; nothing when "## New" is empty.

  rotate <tag>
      after publishing: move the "## New" entries under "## In <version>",
      start an empty "## New", and add the entries to CHANGELOG.md like
      `changelog` does, for main.

<tag> is the release tag, e.g. v1.5.4-ios.18 (version 1.5.4-ios.18, base
version 1.5.4).
"""

import re
import sys
from pathlib import Path

NOTES = Path("RELEASE_NOTES.md")
CHANGELOG = Path("CHANGELOG.md")
NEW = "## New"
EMPTY_HINT = "<!-- Changes for the next release go here, one '- ' entry each. -->"


def version_of(tag: str) -> str:
    return tag[1:] if tag.startswith("v") else tag


def base_version_of(tag: str) -> str:
    match = re.match(r"\d+(\.\d+)*", version_of(tag))
    if not match:
        raise SystemExit(f"not a release tag: {tag}")
    return match.group(0)


def split_new(text: str):
    """(before, entries, after) around the "## New" section."""
    lines = text.split("\n")
    try:
        start = lines.index(NEW)
    except ValueError:
        raise SystemExit(f'{NOTES}: no "{NEW}" section')
    end = start + 1
    while end < len(lines) and not lines[end].startswith("## "):
        end += 1
    body = lines[start + 1 : end]
    return lines[:start], body, lines[end:]


def entries_of(body):
    """The '- ' entries of a section, continuation lines joined."""
    entries = []
    for line in body:
        if line.startswith("- "):
            entries.append(line[2:].strip())
        elif line.strip() and not line.strip().startswith("<!--") and entries:
            entries[-1] += " " + line.strip()
    return entries


def plain(entry: str) -> str:
    """Markdown entry as plain text for the in-app changelog."""
    text = entry.replace("**", "").replace("`", "")
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    return text.strip()


def body(tag: str, out: str, allow_empty: bool) -> None:
    before, section, after = split_new(NOTES.read_text())
    if not entries_of(section) and not allow_empty:
        raise SystemExit(f'{NOTES}: "{NEW}" has no entries for {tag}')
    kept = [line for line in section if not line.strip().startswith("<!--")]
    heading = [f"{NEW} in {version_of(tag)}"] if entries_of(section) else []
    lines = before + heading + kept + after
    Path(out).write_text("\n".join(lines))


def rotate(tag: str) -> None:
    text = NOTES.read_text()
    before, section, after = split_new(text)
    entries = entries_of(section)
    if not entries:
        raise SystemExit(f'{NOTES}: "{NEW}" has no entries to move')
    released = [line for line in section if not line.strip().startswith("<!--")]
    while released and not released[-1].strip():
        released.pop()
    lines = (
        before
        + [NEW, EMPTY_HINT, "", f"## In {version_of(tag)}"]
        + released
        + [""]
        + after
    )
    NOTES.write_text(re.sub(r"\n{3,}", "\n\n", "\n".join(lines)))
    add_to_changelog(tag, entries)


def changelog(tag: str) -> None:
    _, section, _ = split_new(NOTES.read_text())
    entries = entries_of(section)
    if entries:
        add_to_changelog(tag, entries)


def add_to_changelog(tag: str, entries) -> None:
    """Adds [entries] as plain text at the top of the base version's
    CHANGELOG.md section (the section is created when missing)."""
    base = base_version_of(tag)
    lines = CHANGELOG.read_text().split("\n")
    heading = f"## {base}"
    added = [f"* {plain(entry)}" for entry in entries]
    if heading in lines:
        at = lines.index(heading) + 1
        lines[at:at] = added
    else:
        lines[0:0] = [heading] + added + [""]
    CHANGELOG.write_text("\n".join(lines))


def main(args) -> None:
    if len(args) >= 3 and args[0] == "body":
        body(args[1], args[2], "--allow-empty" in args[3:])
    elif len(args) == 2 and args[0] == "rotate":
        rotate(args[1])
    elif len(args) == 2 and args[0] == "changelog":
        changelog(args[1])
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
