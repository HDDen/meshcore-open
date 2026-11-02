"""Check actual merged manifests from Android Auto enabled/disabled builds.

This reads XML artifacts produced by Gradle; it does not run Gradle, build an
APK, or infer the result from build.gradle.kts. Optionally pass a default build
to verify that omitting the property is equivalent to androidAuto=true.
"""

import argparse
from pathlib import Path
import xml.etree.ElementTree as ET


ANDROID = "{http://schemas.android.com/apk/res/android}"
CAR_APPLICATION = "com.google.android.gms.car.application"
ACTION_RECEIVER = "com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver"


def read_manifest(path):
    root = ET.parse(path).getroot()
    applications = root.findall("application")
    if root.tag != "manifest" or len(applications) != 1:
        raise ValueError(f"Expected one manifest/application in {path}")
    application = applications[0]
    receivers = [
        node for node in application.findall("receiver")
        if node.get(ANDROID + "name") == ACTION_RECEIVER
    ]
    if len(receivers) != 1 or receivers[0].get(ANDROID + "exported") != "false":
        raise ValueError(f"The common notification action receiver changed: {path}")
    for attribute, expected in [
        ("fullBackupContent", "@xml/mco_backup_rules"),
        ("dataExtractionRules", "@xml/mco_data_extraction_rules"),
    ]:
        if application.get(ANDROID + attribute) != expected:
            raise ValueError(f"The common {attribute} reference changed: {path}")
    return root, application


def normalized(element):
    # Attribute and sibling order do not change manifest declarations. Retain
    # all values and duplicates so unrelated changes cannot pass unnoticed.
    return (
        element.tag,
        tuple(sorted(element.attrib.items())),
        (element.text or "").strip(),
        tuple(sorted((normalized(child) for child in element), key=repr)),
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--enabled", type=Path, required=True)
    parser.add_argument("--disabled", type=Path, required=True)
    parser.add_argument("--default", type=Path)
    args = parser.parse_args()
    try:
        enabled, enabled_app = read_manifest(args.enabled)
        disabled, disabled_app = read_manifest(args.disabled)
        if args.default is not None:
            default, _ = read_manifest(args.default)
            if normalized(default) != normalized(enabled):
                raise ValueError("Default build differs from androidAuto=true")

        car_entries = [
            node for node in enabled_app.findall("meta-data")
            if node.get(ANDROID + "name") == CAR_APPLICATION
        ]
        if len(car_entries) != 1:
            raise ValueError("Enabled build must contain one Android Auto declaration")
        if car_entries[0].get(ANDROID + "resource") != "@xml/automotive_app_desc":
            raise ValueError("Enabled build has an unexpected Android Auto descriptor")
        if any(
            node.get(ANDROID + "name") == CAR_APPLICATION
            for node in disabled_app.findall("meta-data")
        ):
            raise ValueError("Disabled build still declares Android Auto")

        enabled_app.remove(car_entries[0])
        if normalized(enabled) != normalized(disabled):
            raise ValueError("Builds differ beyond the Android Auto declaration")
    except (OSError, ET.ParseError, ValueError) as error:
        parser.exit(1, f"Android Auto manifest check failed: {error}\n")
    print("Android Auto manifests match; common declarations are preserved.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
