#!/usr/bin/env python3

import argparse
from pathlib import Path
import xml.etree.ElementTree as ET


SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Add a signed release to a Sparkle appcast")
    parser.add_argument("appcast", type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--publication-date", required=True)
    parser.add_argument("--download-url", required=True)
    parser.add_argument("--signature", required=True)
    parser.add_argument("--size", required=True)
    parser.add_argument("--minimum-system-version", default="14.0")
    return parser.parse_args()


def validate_arguments(arguments: argparse.Namespace) -> None:
    if not arguments.appcast.is_file():
        raise SystemExit(f"Appcast does not exist: {arguments.appcast}")
    if not arguments.build_number.isdigit():
        raise SystemExit("Build number must contain only digits")
    if not arguments.size.isdigit() or int(arguments.size) <= 0:
        raise SystemExit("Artifact size must be a positive integer")


def add_release(arguments: argparse.Namespace) -> None:
    ET.register_namespace("sparkle", SPARKLE_NAMESPACE)
    tree = ET.parse(arguments.appcast)
    channel = tree.getroot().find("channel")
    if channel is None:
        raise SystemExit("Appcast has no channel element")

    version_element = f"{{{SPARKLE_NAMESPACE}}}shortVersionString"
    for existing_item in channel.findall("item"):
        existing_version = existing_item.find(version_element)
        if existing_version is not None and existing_version.text == arguments.version:
            channel.remove(existing_item)

    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = f"Version {arguments.version}"
    ET.SubElement(item, "pubDate").text = arguments.publication_date
    ET.SubElement(item, f"{{{SPARKLE_NAMESPACE}}}version").text = arguments.build_number
    ET.SubElement(item, version_element).text = arguments.version
    ET.SubElement(
        item,
        f"{{{SPARKLE_NAMESPACE}}}minimumSystemVersion",
    ).text = arguments.minimum_system_version

    enclosure = ET.SubElement(item, "enclosure")
    enclosure.set("url", arguments.download_url)
    enclosure.set(f"{{{SPARKLE_NAMESPACE}}}edSignature", arguments.signature)
    enclosure.set("length", arguments.size)
    enclosure.set("type", "application/octet-stream")

    ET.indent(tree, space="  ")
    tree.write(arguments.appcast, encoding="utf-8", xml_declaration=True)
    with arguments.appcast.open("ab") as appcast_file:
        appcast_file.write(b"\n")


def main() -> None:
    arguments = parse_arguments()
    validate_arguments(arguments)
    add_release(arguments)


if __name__ == "__main__":
    main()
