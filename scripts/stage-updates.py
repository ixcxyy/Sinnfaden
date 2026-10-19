#!/usr/bin/env python3
"""Stage only signed, feed-referenced files for Cloudflare's free static hosting."""

import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
from urllib.parse import unquote, urlsplit
import xml.etree.ElementTree as ET

MAX_ASSET_BYTES = 25 * 1024 * 1024
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
KEY_ACCOUNT = "at.klar.promptcoach"


def stage(source, destination, feed_url, verify):
    url = urlsplit(feed_url)
    if (url.scheme != "https" or not url.hostname or url.username is not None
            or url.password is not None or url.query or url.fragment
            or not url.path.endswith("/appcast.xml")):
        raise ValueError("The feed must be an HTTPS appcast.xml URL without credentials or query parameters")
    prefix = feed_url[:-len("appcast.xml")]
    feed = source / "appcast.xml"
    if feed.is_symlink() or not feed.is_file() or feed.stat().st_size > 1024 * 1024:
        raise ValueError("Missing, linked, or oversized appcast")
    verify(feed, None)
    root = ET.fromstring(feed.read_bytes())
    references = [(node.get("url"), node) for node in root.iter("enclosure")]
    references += [(node.text, node) for node in root.iter(SPARKLE + "releaseNotesLink")]
    if not any(True for _ in root.iter("enclosure")):
        raise ValueError("An update feed must contain a release archive")
    files = {"appcast.xml": feed}
    for remote, node in references:
        if not remote or not remote.startswith(prefix):
            raise ValueError("Every release file must be hosted beside this appcast")
        name = unquote(remote[len(prefix):])
        if (not name or name.startswith(".") or any(c in name for c in "/\\?#\0")
                or Path(name).suffix not in {".zip", ".delta", ".md", ".html", ".txt"}):
            raise ValueError("Unsafe release filename")
        path = source / name
        if path.is_symlink() or not path.is_file():
            raise ValueError("A feed-referenced release file is missing or is a symlink")
        if path.stat().st_size > MAX_ASSET_BYTES:
            raise ValueError("Release exceeds Cloudflare's 25 MiB file limit; no paid fallback is enabled")
        length = node.get("length") or node.get(SPARKLE + "length")
        if length is not None and (not length.isdecimal() or int(length) != path.stat().st_size):
            raise ValueError("Release file length does not match the signed feed")
        signature = node.get(SPARKLE + "edSignature")
        if not signature:
            raise ValueError("Release files must have an Ed25519 signature")
        verify(path, signature)
        files[name] = path
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix="update-site-", dir=destination.parent))
    backup = temporary.with_name(temporary.name + "-previous")
    try:
        for name, path in files.items():
            shutil.copyfile(path, temporary / name)
        (temporary / "_headers").write_text(
            "/*\n  X-Content-Type-Options: nosniff\n"
            "/appcast.xml\n  Content-Type: application/rss+xml; charset=utf-8\n"
            "  Cache-Control: no-cache\n", encoding="utf-8")
        if destination.exists():
            destination.rename(backup)
        try:
            temporary.rename(destination)
        except OSError:
            if backup.exists():
                backup.rename(destination)
            raise
        if backup.exists():
            shutil.rmtree(backup)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)
    return sorted(files)


def main():
    project = Path(__file__).resolve().parent.parent
    app = Path(os.environ.get("KLAR_APP_PATH", project / "Artifacts/Sinnfaden.app"))
    with (app / "Contents/Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    tools = project / ".build/artifacts/sparkle/Sparkle/bin"
    public_key = subprocess.check_output(
        [str(tools / "generate_keys"), "--account", KEY_ACCOUNT, "-p"], text=True).strip()
    if info.get("SUPublicEDKey") != public_key:
        raise ValueError("App public key does not match Sinnfaden's Keychain signing key")

    def verify(path, signature):
        command = [str(tools / "sign_update"), "--account", KEY_ACCOUNT, "--verify", str(path)]
        if signature is not None:
            command.append(signature)
        subprocess.run(command, check=True)

    files = stage(
        Path(os.environ.get("KLAR_UPDATE_OUTPUT", project / "Artifacts/updates")),
        project / "Artifacts/update-site", info.get("SUFeedURL", ""), verify)
    print(f"Verified and staged {len(files)} signed files. Nothing uploaded.")


if __name__ == "__main__":
    main()
