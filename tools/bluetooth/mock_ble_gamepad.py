#!/usr/bin/env python3
"""Temporary BlueZ HID-over-GATT gamepad fixture for Brick qualification.

Run as root on a Linux host with a peripheral-capable BlueZ adapter.  Once a
central subscribes, the fixture taps button 1 every two seconds.  This is a
test fixture, not product code.
"""

import signal
import sys

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib


BLUEZ = "org.bluez"
OM = "org.freedesktop.DBus.ObjectManager"
PROPS = "org.freedesktop.DBus.Properties"
GATT_MANAGER = "org.bluez.GattManager1"
GATT_SERVICE = "org.bluez.GattService1"
GATT_CHARACTERISTIC = "org.bluez.GattCharacteristic1"
GATT_DESCRIPTOR = "org.bluez.GattDescriptor1"
ADV_MANAGER = "org.bluez.LEAdvertisingManager1"
ADVERTISEMENT = "org.bluez.LEAdvertisement1"

UUID_BASE = "{}-0000-1000-8000-00805f9b34fb"


def uuid(short):
    return UUID_BASE.format(short.lower().zfill(8))


def bytes_(values):
    return dbus.Array([dbus.Byte(value) for value in values], signature="y")


class InvalidArgs(dbus.exceptions.DBusException):
    _dbus_error_name = "org.freedesktop.DBus.Error.InvalidArgs"


class NotSupported(dbus.exceptions.DBusException):
    _dbus_error_name = "org.bluez.Error.NotSupported"


class Application(dbus.service.Object):
    def __init__(self, bus):
        self.path = "/org/brick/mock_gamepad"
        self.services = [DeviceInformation(bus, 0), Battery(bus, 1), Hid(bus, 2)]
        super().__init__(bus, self.path)

    @dbus.service.method(OM, out_signature="a{oa{sa{sv}}}")
    def GetManagedObjects(self):
        result = {}
        for service in self.services:
            result[service.path] = service.properties()
            for characteristic in service.characteristics:
                result[characteristic.path] = characteristic.properties()
                for descriptor in characteristic.descriptors:
                    result[descriptor.path] = descriptor.properties()
        return result


class Service(dbus.service.Object):
    BASE = "/org/brick/mock_gamepad/service"

    def __init__(self, bus, index, service_uuid):
        self.path = f"{self.BASE}{index}"
        self.service_uuid = service_uuid
        self.characteristics = []
        super().__init__(bus, self.path)

    def add(self, characteristic):
        self.characteristics.append(characteristic)

    def properties(self):
        return {GATT_SERVICE: {
            "UUID": self.service_uuid,
            "Primary": dbus.Boolean(True),
            "Characteristics": dbus.Array(
                [dbus.ObjectPath(c.path) for c in self.characteristics], signature="o"
            ),
        }}

    @dbus.service.method(PROPS, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        if interface != GATT_SERVICE:
            raise InvalidArgs()
        return self.properties()[GATT_SERVICE]


class Characteristic(dbus.service.Object):
    def __init__(self, bus, index, characteristic_uuid, flags, service):
        self.path = f"{service.path}/char{index}"
        self.characteristic_uuid = characteristic_uuid
        self.flags = dbus.Array(flags, signature="s")
        self.service = service
        self.descriptors = []
        super().__init__(bus, self.path)

    def properties(self):
        return {GATT_CHARACTERISTIC: {
            "Service": dbus.ObjectPath(self.service.path),
            "UUID": self.characteristic_uuid,
            "Flags": self.flags,
            "Descriptors": dbus.Array(
                [dbus.ObjectPath(d.path) for d in self.descriptors], signature="o"
            ),
        }}

    @dbus.service.method(PROPS, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        if interface != GATT_CHARACTERISTIC:
            raise InvalidArgs()
        return self.properties()[GATT_CHARACTERISTIC]

    @dbus.service.method(GATT_CHARACTERISTIC, in_signature="a{sv}", out_signature="ay")
    def ReadValue(self, options):
        raise NotSupported()

    @dbus.service.method(GATT_CHARACTERISTIC, in_signature="aya{sv}")
    def WriteValue(self, value, options):
        raise NotSupported()

    @dbus.service.method(GATT_CHARACTERISTIC)
    def StartNotify(self):
        raise NotSupported()

    @dbus.service.method(GATT_CHARACTERISTIC)
    def StopNotify(self):
        raise NotSupported()

    @dbus.service.signal(PROPS, signature="sa{sv}as")
    def PropertiesChanged(self, interface, changed, invalidated):
        pass


class StaticCharacteristic(Characteristic):
    def __init__(self, bus, index, characteristic_uuid, value, service, flags=("read",)):
        self.value = bytes_(value)
        super().__init__(bus, index, characteristic_uuid, flags, service)

    def ReadValue(self, options):
        return self.value


class WritableCharacteristic(StaticCharacteristic):
    def WriteValue(self, value, options):
        self.value = bytes_(value)


class Descriptor(dbus.service.Object):
    def __init__(self, bus, index, descriptor_uuid, value, characteristic):
        self.path = f"{characteristic.path}/desc{index}"
        self.descriptor_uuid = descriptor_uuid
        self.value = bytes_(value)
        self.characteristic = characteristic
        super().__init__(bus, self.path)

    def properties(self):
        return {GATT_DESCRIPTOR: {
            "Characteristic": dbus.ObjectPath(self.characteristic.path),
            "UUID": self.descriptor_uuid,
            "Flags": dbus.Array(["read"], signature="s"),
        }}

    @dbus.service.method(PROPS, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        if interface != GATT_DESCRIPTOR:
            raise InvalidArgs()
        return self.properties()[GATT_DESCRIPTOR]

    @dbus.service.method(GATT_DESCRIPTOR, in_signature="a{sv}", out_signature="ay")
    def ReadValue(self, options):
        return self.value


class DeviceInformation(Service):
    def __init__(self, bus, index):
        super().__init__(bus, index, uuid("180a"))
        self.add(StaticCharacteristic(bus, 0, uuid("2a29"), b"Brick qualification fixture", self))
        # Bluetooth SIG source, vendor/product/version are deliberately test-only.
        self.add(StaticCharacteristic(bus, 1, uuid("2a50"), [1, 0xFF, 0xFF, 1, 0, 1, 0], self))


class Battery(Service):
    def __init__(self, bus, index):
        super().__init__(bus, index, uuid("180f"))
        self.add(StaticCharacteristic(bus, 0, uuid("2a19"), [100], self))


class InputReport(Characteristic):
    def __init__(self, bus, index, service):
        super().__init__(bus, index, uuid("2a4d"), ["read", "notify"], service)
        self.value = [0, 0, 8, 0, 0]
        self.notifying = False
        self.pressed = False
        self.descriptors.append(Descriptor(bus, 0, uuid("2908"), [0, 1], self))

    def ReadValue(self, options):
        return bytes_(self.value)

    def StartNotify(self):
        if self.notifying:
            return
        self.notifying = True
        print("central subscribed; tapping button 1 every two seconds", flush=True)
        GLib.timeout_add_seconds(1, self.tick)

    def StopNotify(self):
        self.notifying = False

    def tick(self):
        if not self.notifying:
            return False
        self.pressed = not self.pressed
        self.value[0] = 1 if self.pressed else 0
        self.PropertiesChanged(
            GATT_CHARACTERISTIC,
            {"Value": bytes_(self.value)},
            [],
        )
        print("button 1 " + ("pressed" if self.pressed else "released"), flush=True)
        return True


class Hid(Service):
    # Report-only gamepad: 16 buttons, an 8-way hat, and signed X/Y axes.
    REPORT_MAP = [
        0x05, 0x01, 0x09, 0x05, 0xA1, 0x01,
        0x05, 0x09, 0x19, 0x01, 0x29, 0x10, 0x15, 0x00, 0x25, 0x01,
        0x75, 0x01, 0x95, 0x10, 0x81, 0x02,
        0x05, 0x01, 0x09, 0x39, 0x15, 0x00, 0x25, 0x07,
        0x35, 0x00, 0x46, 0x3B, 0x01, 0x65, 0x14,
        0x75, 0x04, 0x95, 0x01, 0x81, 0x42,
        0x65, 0x00, 0x75, 0x04, 0x95, 0x01, 0x81, 0x03,
        0x09, 0x30, 0x09, 0x31, 0x15, 0x81, 0x25, 0x7F,
        0x75, 0x08, 0x95, 0x02, 0x81, 0x02, 0xC0,
    ]

    def __init__(self, bus, index):
        super().__init__(bus, index, uuid("1812"))
        self.add(StaticCharacteristic(bus, 0, uuid("2a4a"), [0x11, 0x01, 0, 0x02], self))
        self.add(StaticCharacteristic(bus, 1, uuid("2a4b"), self.REPORT_MAP, self))
        self.add(WritableCharacteristic(bus, 2, uuid("2a4e"), [1], self,
                                        ("read", "write-without-response")))
        self.add(WritableCharacteristic(bus, 3, uuid("2a4c"), [0], self,
                                        ("write-without-response",)))
        self.input_report = InputReport(bus, 4, self)
        self.add(self.input_report)


class Advertisement(dbus.service.Object):
    path = "/org/brick/mock_gamepad/advertisement0"

    def __init__(self, bus):
        super().__init__(bus, self.path)

    def properties(self):
        return {ADVERTISEMENT: {
            "Type": "peripheral",
            "ServiceUUIDs": dbus.Array([uuid("1812"), uuid("180f"), uuid("180a")], signature="s"),
            "LocalName": dbus.String("Brick Test Controller"),
            "Appearance": dbus.UInt16(0x03C4),
            "Discoverable": dbus.Boolean(True),
        }}

    @dbus.service.method(PROPS, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        if interface != ADVERTISEMENT:
            raise InvalidArgs()
        return self.properties()[ADVERTISEMENT]

    @dbus.service.method(ADVERTISEMENT)
    def Release(self):
        print("advertisement released", flush=True)


def find_adapter(bus):
    objects = dbus.Interface(bus.get_object(BLUEZ, "/"), OM).GetManagedObjects()
    for path, interfaces in objects.items():
        if GATT_MANAGER in interfaces and ADV_MANAGER in interfaces:
            return path
    raise RuntimeError("no adapter exposes both GATT and advertising managers")


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    adapter = find_adapter(bus)
    app = Application(bus)
    advertisement = Advertisement(bus)
    gatt = dbus.Interface(bus.get_object(BLUEZ, adapter), GATT_MANAGER)
    advertising = dbus.Interface(bus.get_object(BLUEZ, adapter), ADV_MANAGER)
    loop = GLib.MainLoop()

    signal.signal(signal.SIGINT, lambda *_: loop.quit())
    signal.signal(signal.SIGTERM, lambda *_: loop.quit())
    failures = []

    def registration_failed(kind, error):
        failures.append(error)
        print(f"{kind} registration failed: {error}", file=sys.stderr, flush=True)
        loop.quit()

    def advertisement_registered():
        print("registered HID-over-GATT gamepad; waiting for a central", flush=True)

    # BlueZ calls GetManagedObjects while registering the application, so this
    # must be asynchronous with the GLib loop running (a synchronous call
    # deadlocks waiting for our own D-Bus method dispatch).
    gatt.RegisterApplication(
        app.path,
        {},
        reply_handler=lambda: advertising.RegisterAdvertisement(
            advertisement.path,
            {},
            reply_handler=advertisement_registered,
            error_handler=lambda error: registration_failed("advertisement", error),
        ),
        error_handler=lambda error: registration_failed("GATT application", error),
    )
    try:
        loop.run()
    finally:
        try:
            advertising.UnregisterAdvertisement(advertisement.path)
        except dbus.exceptions.DBusException:
            pass
        try:
            gatt.UnregisterApplication(app.path)
        except dbus.exceptions.DBusException:
            pass
    if failures:
        raise failures[0]


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"mock gamepad failed: {error}", file=sys.stderr)
        sys.exit(1)
