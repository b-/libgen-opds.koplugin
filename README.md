# libgen-opds KOReader Plugin

*Run libgen-opds server from within KOReader.*

This plugin adds a menu item to start and stop the libgen-opds server in the *Network* section of the KOReader menu.

Tested on jailbroken Kindle Paperwhite 4 (2018). It probably works on other devices (including Kobos and other jailbroken Kindles). Please report back (in the Issues tracker!) if it does or doesn't.

## Easy Installation (with bundled `libgen-opds` binary)

1. Download and extract [the latest release](https://github.com/b-/libgen-opds.koplugin/releases/latest) for your platform, and copy it to the `plugins/libgen-opds.koplugin` directory of your KOReader installation.

## Custom Installation (add your own `libgen-opds` binary)

1. Copy this repository (at least *_meta.lua* and *main.lua*) into the *plugins/libgen-opds.koplugin* directory of your KOReader installation.
2. Download a libgen-opds binary appropriate for your device from [the libgen-opds website](https://github.com/libgen-opds/libgen-opds/releases/latest) (most likely `linux-armv7-libgen-opds.tar.gz`).
3. Extract the archive and copy the `libgen-opds` binary to the `plugins/libgen-opds.koplugin` directory.

Done! Restart KOReader and you should find the libgen-opds option in the *Network* section under the gear icon in the top menu. After starting libgen-opds, you can use the web GUI to copy files to and from your e-reader. Go to <http://x.x.x.x>, replacing `x.x.x.x` with your e-reader's IP address. The default username and password are `admin` and `admin`, and can be changed from the web interface.

   This will make the libgen-opds GUI available to all devices on the network, so make sure you set a username and strong password in the GUI!

   If you need to reset the password or settings, delete the `plugins/libgen-opds.koplugin/libgen-opds/libgen-opds.db` file.

The libgen-opds binary, configuration files, log files and other data are all stored in `plugins/libgen-opds.koplugin/libgen-opds/` in the KOReader directory.

## Troubleshooting

- The libgen-opds menu item does not appear after installation.

  First, restart KOReader. If that doesn't help, check if you correctly installed the `libgen-opds` binary. The `libgen-opds.koplugin` directory should contain `_meta.lua`, `main.lua`, and a folder called `libgen-opds` into which you should have copied the latest version of the `libgen-opds` binary. Finally, it may be the case that your device does not have the `start-stop-daemon` command available, which we use to run libgen-opds as a background process.

- libgen-opds stops after a moment: the checkbox uncheks itself after reopening the menu.

  This means that libgen-opds is unable to start up. Have a look at the libgen-opds log files at `plugins/libgen-opds.koplugin/libgen-opds` to find out why libgen-opds is unable to start.

---

This code is primarily based on [syncthing.koplugin](https://github.com/arthurrump/syncthing.koplugin), which is itself primarily based on [SSH.koplugin](https://github.com/koreader/koreader/tree/master/plugins/SSH.koplugin), all of which are available under the [AGPL-3.0 license](https://github.com/koreader/koreader/blob/master/COPYING).
