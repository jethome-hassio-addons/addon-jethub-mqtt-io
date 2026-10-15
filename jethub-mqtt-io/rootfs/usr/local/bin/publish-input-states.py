#!/usr/bin/env python3
"""Publish retained digital-input states for gpio2mqtt (addon workaround).

Assumes legacy mqtt-io topic layout when mqtt.legacy_mqttio is true (addon default):
  {topic_prefix}/input/{name}

Payloads default to ON/OFF (mqtt-io / gpio2mqtt example defaults).
Reads live GPIO via gpioget when the chip is free; in watch mode also caches
MQTT updates from gpio2mqtt and re-publishes on homeassistant/status=online.

Not a substitute for a proper gpio2mqtt fix; topic/payload assumptions may
differ if custom_config changes convention or legacy_mqttio.
"""
from __future__ import annotations

import argparse
import json
import os
import socket
import struct
import subprocess
import sys
import time
from typing import Any, Dict, List, Optional, Tuple

try:
    import yaml
except ImportError:  # pragma: no cover
    print("[publish-input-states] python3-yaml required", file=sys.stderr)
    sys.exit(1)


def log(msg: str) -> None:
    print(f"[publish-input-states] {msg}", flush=True)


def load_config(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    if not isinstance(data, dict):
        raise ValueError("config root must be a mapping")
    return data


def chip_for_module(config: dict, module_name: str) -> str:
    for mod in config.get("gpio_modules") or []:
        if mod.get("name") == module_name:
            chip = mod.get("chip") or "/dev/gpiochip0"
            return str(chip)
    return "/dev/gpiochip0"


def input_specs(config: dict) -> List[dict]:
    specs = []
    for item in config.get("digital_inputs") or []:
        name = item.get("name")
        if not name:
            continue
        specs.append(
            {
                "name": str(name),
                "module": str(item.get("module") or "gpio"),
                "pin": item.get("pin"),
                "inverted": bool(item.get("inverted", False)),
                "on_payload": str(item.get("on_payload", "ON")),
                "off_payload": str(item.get("off_payload", "OFF")),
            }
        )
    return specs


def state_topic(prefix: str, name: str, legacy: bool) -> str:
    prefix = prefix.strip("/")
    if legacy:
        return f"{prefix}/input/{name}"
    # Best-effort non-legacy guess (gpio2mqtt source is private).
    return f"{prefix}/input/{name}"


def read_pin(chip: str, pin: Any, inverted: bool) -> Optional[bool]:
    """Return logical on/off (True=on) or None on failure."""
    if pin is None:
        return None
    pin_s = str(pin)
    try:
        proc = subprocess.run(
            ["gpioget", chip, pin_s],
            check=False,
            capture_output=True,
            text=True,
            timeout=2,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired) as exc:
        log(f"gpioget unavailable/failed for {chip} {pin_s}: {exc}")
        return None
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or "").strip()
        log(f"gpioget {chip} {pin_s} rc={proc.returncode}: {err}")
        return None
    raw = (proc.stdout or "").strip().split()[-1:] or [""]
    try:
        level = int(raw[0])
    except (ValueError, IndexError):
        log(f"gpioget unexpected output for {chip} {pin_s}: {proc.stdout!r}")
        return None
    logical = bool(level)
    if inverted:
        logical = not logical
    return logical


class MiniMqtt:
    """Minimal MQTT 3.1.1 client (QoS0/1 publish + subscribe)."""

    def __init__(
        self,
        host: str,
        port: int,
        username: str = "",
        password: str = "",
        client_id: str = "jethub-input-states",
        keepalive: int = 60,
    ) -> None:
        self.host = host
        self.port = int(port)
        self.username = username or ""
        self.password = password or ""
        self.client_id = client_id
        self.keepalive = keepalive
        self.sock: Optional[socket.socket] = None
        self._buf = bytearray()

    def connect(self, timeout: float = 15.0) -> None:
        self.sock = socket.create_connection((self.host, self.port), timeout=timeout)
        self.sock.settimeout(5.0)
        flags = 0x02  # clean session
        payload = self._str(self.client_id)
        if self.username:
            flags |= 0x80
            payload += self._str(self.username)
            if self.password:
                flags |= 0x40
                payload += self._str(self.password)
        variable = self._str("MQTT") + bytes([0x04, flags]) + struct.pack("!H", self.keepalive)
        self._send_packet(0x10, variable + payload)
        ptype, data = self._read_packet()
        if ptype != 0x20 or len(data) < 2 or data[1] != 0x00:
            raise OSError(f"MQTT CONNACK failed: type={ptype:#x} data={data!r}")

    def close(self) -> None:
        if self.sock:
            try:
                self._send_packet(0xE0, b"")  # DISCONNECT
            except OSError:
                pass
            try:
                self.sock.close()
            except OSError:
                pass
            self.sock = None

    def publish(self, topic: str, payload: str, retain: bool = True, qos: int = 1) -> None:
        if self.sock is None:
            raise OSError("not connected")
        qos = 1 if qos else 0
        flags = 0x30 | (qos << 1) | (0x01 if retain else 0)
        pkt_id = b""
        body = self._str(topic)
        if qos:
            # Fixed packet id 1 is fine for our low-rate helper.
            pkt_id = struct.pack("!H", 1)
            body += pkt_id
        body += payload.encode("utf-8")
        self._send_raw(flags, body)
        if qos:
            ptype, _ = self._read_packet()
            if ptype != 0x40:
                raise OSError(f"expected PUBACK, got {ptype:#x}")

    def subscribe(self, topic: str, qos: int = 0) -> None:
        body = struct.pack("!H", 1) + self._str(topic) + bytes([qos & 0x03])
        self._send_packet(0x82, body)
        ptype, _ = self._read_packet()
        if ptype != 0x90:
            raise OSError(f"expected SUBACK, got {ptype:#x}")

    def ping(self) -> None:
        self._send_packet(0xC0, b"")

    def read_message(self, timeout: float) -> Optional[Tuple[str, str]]:
        if self.sock is None:
            return None
        self.sock.settimeout(timeout)
        try:
            while True:
                ptype, data = self._read_packet()
                if ptype == 0xD0:  # PINGRESP
                    continue
                if (ptype & 0xF0) == 0x30:  # PUBLISH
                    topic_len = struct.unpack("!H", data[0:2])[0]
                    topic = data[2 : 2 + topic_len].decode("utf-8", "replace")
                    idx = 2 + topic_len
                    qos = (ptype >> 1) & 0x03
                    if qos:
                        idx += 2
                    payload = data[idx:].decode("utf-8", "replace")
                    if qos == 1:
                        # PUBACK with packet id from message
                        pid = data[2 + topic_len : 2 + topic_len + 2]
                        self._send_packet(0x40, pid)
                    return topic, payload
                # ignore other packets
        except socket.timeout:
            return None

    @staticmethod
    def _str(s: str) -> bytes:
        b = s.encode("utf-8")
        return struct.pack("!H", len(b)) + b

    def _encode_len(self, length: int) -> bytes:
        out = bytearray()
        while True:
            digit = length % 128
            length //= 128
            if length:
                digit |= 0x80
            out.append(digit)
            if not length:
                break
        return bytes(out)

    def _send_packet(self, type_flags: int, payload: bytes) -> None:
        self._send_raw(type_flags, payload)

    def _send_raw(self, type_flags: int, payload: bytes) -> None:
        assert self.sock is not None
        self.sock.sendall(bytes([type_flags]) + self._encode_len(len(payload)) + payload)

    def _read_packet(self) -> Tuple[int, bytes]:
        assert self.sock is not None
        while len(self._buf) < 2:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise OSError("MQTT connection closed")
            self._buf.extend(chunk)
        ptype = self._buf[0]
        multiplier = 1
        value = 0
        idx = 1
        while True:
            while len(self._buf) <= idx:
                chunk = self.sock.recv(4096)
                if not chunk:
                    raise OSError("MQTT connection closed")
                self._buf.extend(chunk)
            encoded = self._buf[idx]
            idx += 1
            value += (encoded & 127) * multiplier
            if not (encoded & 128):
                break
            multiplier *= 128
            if multiplier > 128 * 128 * 128:
                raise OSError("MQTT remaining length overflow")
        while len(self._buf) < idx + value:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise OSError("MQTT connection closed")
            self._buf.extend(chunk)
        data = bytes(self._buf[idx : idx + value])
        del self._buf[: idx + value]
        return ptype, data


def mqtt_from_config(config: dict, client_id_suffix: str) -> MiniMqtt:
    mqtt = config.get("mqtt") or {}
    host = str(mqtt.get("host") or os.environ.get("GPIO2MQTT_MQTT_HOST") or "localhost")
    port = int(mqtt.get("port") or os.environ.get("GPIO2MQTT_MQTT_PORT") or 1883)
    user = str(mqtt.get("user") or os.environ.get("GPIO2MQTT_MQTT_USER") or "")
    password = str(mqtt.get("password") or os.environ.get("GPIO2MQTT_MQTT_PASS") or "")
    base_id = str(mqtt.get("client_id") or "jethub-mqtt-io")
    return MiniMqtt(
        host=host,
        port=port,
        username=user,
        password=password,
        client_id=f"{base_id}-{client_id_suffix}"[:23],
        keepalive=int(mqtt.get("keepalive") or 60),
    )


def collect_states(config: dict) -> Dict[str, str]:
    """name -> payload from live GPIO."""
    mqtt = config.get("mqtt") or {}
    legacy = bool(mqtt.get("legacy_mqttio", True))
    prefix = str(mqtt.get("topic_prefix") or "jethub-mqtt-io")
    out: Dict[str, str] = {}
    for spec in input_specs(config):
        chip = chip_for_module(config, spec["module"])
        logical = read_pin(chip, spec["pin"], spec["inverted"])
        if logical is None:
            continue
        payload = spec["on_payload"] if logical else spec["off_payload"]
        topic = state_topic(prefix, spec["name"], legacy)
        out[topic] = payload
        log(f"read {spec['name']}: pin={spec['pin']} inverted={spec['inverted']} -> {payload} ({topic})")
    return out


def publish_map(client: MiniMqtt, states: Dict[str, str], qos: int) -> int:
    n = 0
    for topic, payload in states.items():
        client.publish(topic, payload, retain=True, qos=qos)
        log(f"published retain {topic} = {payload!r}")
        n += 1
    return n


def cmd_once(config_path: str) -> int:
    config = load_config(config_path)
    mqtt_cfg = config.get("mqtt") or {}
    qos = int(mqtt_cfg.get("qos") or 1)
    states = collect_states(config)
    if not states:
        log("no input states read; nothing to publish")
        return 0
    client = mqtt_from_config(config, "init")
    try:
        client.connect()
        publish_map(client, states, qos)
    finally:
        client.close()
    return 0


def cmd_watch(config_path: str) -> int:
    config = load_config(config_path)
    mqtt_cfg = config.get("mqtt") or {}
    qos = int(mqtt_cfg.get("qos") or 1)
    legacy = bool(mqtt_cfg.get("legacy_mqttio", True))
    prefix = str(mqtt_cfg.get("topic_prefix") or "jethub-mqtt-io").strip("/")
    input_prefix = f"{prefix}/input/"
    ha_status = "homeassistant/status"

    cache: Dict[str, str] = {}
    # Seed cache from GPIO if possible (may fail once gpio2mqtt holds lines).
    cache.update(collect_states(config))

    backoff = 2
    while True:
        client = mqtt_from_config(config, "watch")
        try:
            client.connect()
            client.subscribe(ha_status, qos=0)
            client.subscribe(f"{input_prefix}+", qos=0)
            log(f"watching {ha_status} and {input_prefix}+")
            backoff = 2
            last_ping = time.time()
            while True:
                msg = client.read_message(timeout=5.0)
                now = time.time()
                if now - last_ping >= 30:
                    try:
                        client.ping()
                    except OSError:
                        raise
                    last_ping = now
                if not msg:
                    continue
                topic, payload = msg
                if topic == ha_status and payload.strip().lower() == "online":
                    log("HA status online — re-publishing retained input states")
                    # Prefer live GPIO; fall back to cache.
                    live = collect_states(config)
                    if live:
                        cache.update(live)
                    if cache:
                        publish_map(client, cache, qos)
                    else:
                        log("no cached/live input states to re-publish")
                elif topic.startswith(input_prefix):
                    cache[topic] = payload
        except Exception as exc:  # noqa: BLE001 — long-running helper
            log(f"watch loop error: {exc}; retry in {backoff}s")
            try:
                client.close()
            except Exception:  # noqa: BLE001
                pass
            time.sleep(backoff)
            backoff = min(backoff * 2, 60)


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, help="gpio2mqtt.yaml path")
    parser.add_argument(
        "--mode",
        choices=("once", "watch"),
        default="once",
        help="once: publish and exit; watch: re-publish on HA birth",
    )
    args = parser.parse_args(argv)
    if args.mode == "once":
        return cmd_once(args.config)
    return cmd_watch(args.config)


if __name__ == "__main__":
    sys.exit(main())
