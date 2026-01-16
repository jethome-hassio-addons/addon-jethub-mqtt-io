#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["pyyaml>=6.0"]
# ///
"""
GPIO Unexport Script for gpio2mqtt

This script reads a gpio2mqtt configuration file, identifies all configured
GPIO pins, and unexports them from sysfs (/sys/class/gpio/) if they are
currently exported.

This is useful when switching from sysfs-based GPIO control to gpiod/gpiocdev,
as sysfs exports can block access to GPIO lines via the character device.

Usage:
    sudo ./gpio-unexport.py config.yaml
    sudo ./gpio-unexport.py --dry-run config.yaml
    sudo uv run gpio-unexport.py config.yaml
"""

import argparse
import os
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("Error: PyYAML is required. Install with: pip install pyyaml")
    sys.exit(1)


def get_gpiochip_base(chip_path: str) -> int | None:
    """
    Get the base GPIO number for a gpiochip.

    Maps /dev/gpiochipN to the corresponding sysfs gpiochip entry.
    The sysfs entries are named by their base number (e.g., gpiochip512),
    not by the /dev device number.
    """
    chip_name = os.path.basename(chip_path)
    if not chip_name.startswith("gpiochip"):
        print(f"Warning: Invalid chip path: {chip_path}")
        return None

    sysfs_path = find_sysfs_gpiochip(chip_path)
    if sysfs_path:
        base_file = sysfs_path / "base"
        if base_file.exists():
            return int(base_file.read_text().strip())

    return None


def find_sysfs_gpiochip(chip_path: str) -> Path | None:
    """Find the sysfs path for a /dev/gpiochipN device."""
    chip_name = os.path.basename(chip_path)

    # Method 1: via /sys/bus/gpio/devices - look in parent's gpio/ subdirectory
    # /sys/bus/gpio/devices/gpiochipN -> /sys/devices/.../gpiochipN
    # The base info is in /sys/devices/.../gpio/gpiochipXXX/base
    dev_chip_path = Path(f"/sys/bus/gpio/devices/{chip_name}")
    if dev_chip_path.exists():
        try:
            resolved = dev_chip_path.resolve()
            # Look in parent directory for gpio/gpiochip* subdirectory
            parent = resolved.parent
            gpio_subdir = parent / "gpio"
            if gpio_subdir.exists():
                for gpio_dir in gpio_subdir.glob("gpiochip*"):
                    if (gpio_dir / "base").exists():
                        return gpio_dir
        except OSError:
            pass

    # Method 2: Match by device number in /sys/bus/gpio/devices
    try:
        dev_stat = os.stat(chip_path)
        dev_major_minor = (os.major(dev_stat.st_rdev), os.minor(dev_stat.st_rdev))

        for entry in Path("/sys/bus/gpio/devices").iterdir():
            if entry.name.startswith("gpiochip"):
                dev_file = entry / "dev"
                if dev_file.exists():
                    dev_content = dev_file.read_text().strip()
                    major, minor = map(int, dev_content.split(":"))
                    if (major, minor) == dev_major_minor:
                        # Found matching device, now find gpio/gpiochip* in parent
                        resolved = entry.resolve()
                        parent = resolved.parent
                        gpio_subdir = parent / "gpio"
                        if gpio_subdir.exists():
                            for gpio_dir in gpio_subdir.glob("gpiochip*"):
                                if (gpio_dir / "base").exists():
                                    return gpio_dir
    except (OSError, ValueError):
        pass

    # Method 3: Direct path in /sys/class/gpio (when names match)
    direct_path = Path(f"/sys/class/gpio/{chip_name}")
    if direct_path.exists():
        return direct_path

    return None


def get_gpiochip_info(chip_path: str) -> dict:
    """Get information about a gpiochip from sysfs."""
    chip_name = os.path.basename(chip_path)

    info = {
        "name": chip_name,
        "path": chip_path,
        "base": None,
        "ngpio": None,
        "label": None,
        "sysfs_name": None,
    }

    sysfs_path = find_sysfs_gpiochip(chip_path)
    if sysfs_path:
        info["sysfs_name"] = sysfs_path.name
        base_file = sysfs_path / "base"
        ngpio_file = sysfs_path / "ngpio"
        label_file = sysfs_path / "label"

        if base_file.exists():
            info["base"] = int(base_file.read_text().strip())
        if ngpio_file.exists():
            info["ngpio"] = int(ngpio_file.read_text().strip())
        if label_file.exists():
            info["label"] = label_file.read_text().strip()

    return info


def is_gpio_exported(gpio_num: int) -> bool:
    """Check if a GPIO is currently exported in sysfs."""
    return Path(f"/sys/class/gpio/gpio{gpio_num}").exists()


def unexport_gpio(gpio_num: int, dry_run: bool = False) -> bool:
    """Unexport a GPIO from sysfs."""
    unexport_path = Path("/sys/class/gpio/unexport")

    if dry_run:
        print(f"  [DRY-RUN] Would unexport GPIO {gpio_num}")
        return True

    try:
        unexport_path.write_text(str(gpio_num))
        print(f"  Unexported GPIO {gpio_num}")
        return True
    except PermissionError:
        print("  Error: Permission denied. Run with sudo.")
        return False
    except OSError as e:
        print(f"  Error unexporting GPIO {gpio_num}: {e}")
        return False


def parse_config(config_path: str) -> dict:
    """Parse gpio2mqtt YAML configuration file."""
    with open(config_path) as f:
        return yaml.safe_load(f)


def collect_gpios_from_config(config: dict) -> list[dict]:
    """
    Collect all GPIO pins from configuration.

    Returns list of dicts with: name, module, pin, chip_path
    """
    gpios = []

    # Build module -> chip mapping
    modules = {}
    for module in config.get("gpio_modules", []):
        modules[module["name"]] = module.get("chip", "/dev/gpiochip0")

    # Collect digital inputs
    for input_cfg in config.get("digital_inputs", []):
        module_name = input_cfg.get("module", "")
        chip_path = modules.get(module_name, "/dev/gpiochip0")
        pin = input_cfg.get("pin")
        if pin is not None:
            gpios.append(
                {
                    "name": input_cfg.get("name", f"input_{pin}"),
                    "module": module_name,
                    "pin": int(pin),
                    "chip_path": chip_path,
                    "type": "input",
                }
            )

    # Collect digital outputs
    for output_cfg in config.get("digital_outputs", []):
        module_name = output_cfg.get("module", "")
        chip_path = modules.get(module_name, "/dev/gpiochip0")
        pin = output_cfg.get("pin")
        if pin is not None:
            gpios.append(
                {
                    "name": output_cfg.get("name", f"output_{pin}"),
                    "module": module_name,
                    "pin": int(pin),
                    "chip_path": chip_path,
                    "type": "output",
                }
            )

    return gpios


def main():
    parser = argparse.ArgumentParser(
        description="Unexport GPIOs from sysfs based on gpio2mqtt config"
    )
    parser.add_argument("config", help="Path to gpio2mqtt configuration file")
    parser.add_argument(
        "--dry-run",
        "-n",
        action="store_true",
        help="Show what would be done without actually unexporting",
    )
    parser.add_argument(
        "--verbose", "-v", action="store_true", help="Show detailed information"
    )
    args = parser.parse_args()

    # Check config file exists
    if not os.path.exists(args.config):
        print(f"Error: Config file not found: {args.config}")
        sys.exit(1)

    # Parse configuration
    print(f"Reading configuration from: {args.config}")
    config = parse_config(args.config)

    # Collect all GPIOs
    gpios = collect_gpios_from_config(config)
    if not gpios:
        print("No GPIO pins found in configuration")
        sys.exit(0)

    print(f"Found {len(gpios)} GPIO pins in configuration\n")

    # Group by chip
    chips = {}
    for gpio in gpios:
        chip_path = gpio["chip_path"]
        if chip_path not in chips:
            chips[chip_path] = {
                "info": get_gpiochip_info(chip_path),
                "gpios": [],
            }
        chips[chip_path]["gpios"].append(gpio)

    # Process each chip
    unexported_count = 0
    skipped_count = 0
    error_count = 0

    for chip_path, chip_data in chips.items():
        chip_info = chip_data["info"]
        print(f"GPIO Chip: {chip_path}")

        if chip_info["base"] is None:
            print(f"  Warning: Could not determine base for {chip_path}")
            print("  (sysfs interface may not be available)")
            continue

        if args.verbose:
            if chip_info["sysfs_name"]:
                print(f"  sysfs: {chip_info['sysfs_name']}")
            print(f"  Base: {chip_info['base']}")
            print(f"  Lines: {chip_info['ngpio']}")
            if chip_info["label"]:
                print(f"  Label: {chip_info['label']}")

        print()

        for gpio in chip_data["gpios"]:
            line_offset = gpio["pin"]
            gpio_num = chip_info["base"] + line_offset
            name = gpio["name"]

            print(f"  {name} (line {line_offset} -> GPIO {gpio_num}):")

            if is_gpio_exported(gpio_num):
                if unexport_gpio(gpio_num, args.dry_run):
                    unexported_count += 1
                else:
                    error_count += 1
            else:
                print("    Not exported, skipping")
                skipped_count += 1

        print()

    # Summary
    print("=" * 40)
    print("Summary:")
    print(f"  Unexported: {unexported_count}")
    print(f"  Skipped (not exported): {skipped_count}")
    if error_count > 0:
        print(f"  Errors: {error_count}")

    if args.dry_run:
        print("\n[DRY-RUN mode - no changes were made]")


if __name__ == "__main__":
    main()
