#!/usr/bin/env python3
"""Sign a macOS ZIP and write the Sparkle appcast.

The Ed25519 private key is intentionally outside the repository. Set
SPARKLE_ED_KEY or keep it at ~/.config/particle-library/sparkle_ed25519.key.
"""
from __future__ import annotations

import argparse
import base64
import datetime as dt
import html
import os
from pathlib import Path
from urllib.parse import urlparse

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


def load_key() -> Ed25519PrivateKey:
    path = Path(
        os.environ.get(
            "SPARKLE_ED_KEY",
            Path.home() / ".config" / "particle-library" / "sparkle_ed25519.key",
        )
    )
    if not path.is_file():
        raise SystemExit(
            f"Sparkle private key not found: {path}. "
            "Set SPARKLE_ED_KEY or restore the key from your password manager."
        )
    return Ed25519PrivateKey.from_private_bytes(path.read_bytes())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("zip", type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--output", type=Path, default=Path("appcast.xml"))
    parser.add_argument("--notes", default="")
    parser.add_argument("--minimum-system", default="12.0")
    args = parser.parse_args()

    parsed = urlparse(args.url)
    if parsed.scheme != "https" or not parsed.netloc:
        raise SystemExit("The enclosure URL must be an https URL with a host.")
    data = args.zip.read_bytes()
    signature = base64.b64encode(load_key().sign(data)).decode()
    published = dt.datetime.now(dt.timezone.utc).strftime(
        "%a, %d %b %Y %H:%M:%S +0000"
    )
    notes = html.escape(args.notes)
    xml = f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Particle Library</title>
    <link>https://github.com/fkguo/Particle-Library</link>
    <description>Particle Library releases</description>
    <language>en</language>
    <item>
      <title>Particle Library {html.escape(args.version)}</title>
      <pubDate>{published}</pubDate>
      <sparkle:version>{html.escape(args.build)}</sparkle:version>
      <sparkle:shortVersionString>{html.escape(args.version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{html.escape(args.minimum_system)}</sparkle:minimumSystemVersion>
      <description><![CDATA[{notes}]]></description>
      <enclosure
        url="{html.escape(args.url, quote=True)}"
        length="{len(data)}"
        type="application/octet-stream"
        sparkle:edSignature="{signature}" />
    </item>
  </channel>
</rss>
'''
    args.output.write_text(xml, encoding="utf-8")
    print(f"wrote {args.output} for {args.version} ({args.build}), {len(data)} bytes")


if __name__ == "__main__":
    main()
