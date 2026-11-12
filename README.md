MicroSocks - multithreaded, small, efficient SOCKS5 server.
===========================================================

a SOCKS5 service that you can run on your remote boxes to tunnel connections
through them, if for some reason SSH doesn't cut it for you.

It's very lightweight, and very light on resources too:

for every client, a thread with a low stack size is spawned.
the main process basically doesn't consume any resources at all.

the only limits are the amount of file descriptors and the RAM.

It's also designed to be robust: it handles resource exhaustion
gracefully by simply denying new connections, instead of calling abort()
as most other programs do these days.

another plus is ease-of-use: no config file necessary, everything can be
done from the command line and doesn't even need any parameters for quick
setup.

History
-------

This is the successor of "rocksocks5", and it was written with
different goals in mind:

- prefer usage of standard libc functions over homegrown ones
- no artificial limits
- do not aim for minimal binary size, but for minimal source code size,
  and maximal readability, reusability, and extensibility.

as a result of that, ipv4, dns, and ipv6 is supported out of the box
and can use the same code, while rocksocks5 has several compile time
defines to bring down the size of the resulting binary to extreme values
like 10 KB static linked when only ipv4 support is enabled.

still, if optimized for size, *this* program when static linked against musl
libc is not even 50 KB. that's easily usable even on the cheapest routers.

compilation/installation
------------------------

    make && sudo make install

if you want to override variables used in the Makefile, such as CC, CFLAGS, LDFLAGS,
prefix: do so in config.mak:

    printf 'CC=i686-musl-linux-gcc\nprefix=/usr\n' > config.mak
    make

command line options
--------------------

    microsocks -1 -q -t timeout -i listenip -p port -u user -P passw -b bindaddr -w wl

```
all arguments are optional.
by default listenip is 0.0.0.0 and port 1080.

-q disables logging.
-b specifies which ip outgoing connections are bound to
-t timeout is specified in seconds, default 0.
   if timeout is set to 0, block until the OS signals activity.
-w allows to specify a comma-separated whitelist of ip addresses,
   that may use the proxy without user/pass authentication.
   e.g. -w 127.0.0.1,192.168.1.1,::1 or just -w 10.0.0.1
   to allow access ONLY to those ips, choose impossible to guess user/pw combo.
-1 activates auth_once mode: once a specific ip address
   authed successfully with user/pass, it is added to a whitelist
   and may use the proxy without auth.
   this is handy for programs like firefox that don't support
   user/pass auth. for it to work you'd basically make one connection
   with another program that supports it, and then you can use firefox too.
```

for example, authenticate once using curl:

    curl --socks5 user:password@listenip:port anyurl


Supported SOCKS5 Features
-------------------------
- authentication: none, password, one-time
- IPv4, IPv6, DNS
- TCP (no UDP at this time)

Troubleshooting
---------------

if you experience segfaults, try raising the `THREAD_STACK_SIZE` in sockssrv.c
for your platform in steps of 4KB.

if this fixes your issue please file a pull request.

microsocks uses the smallest safe thread stack size to minimize overall memory
usage.

Static release builds
---------------------

Run `microsocks -h` to see usage and the build version.

Each release contains Linux ARMv5TE soft-float, AArch64 and x86-64
musl builds, plus a Windows x64 executable. The Windows executable
imports Windows system DLLs, including Winsock and the inbox Universal
CRT on Windows 10 and later. No extra runtime DLLs are bundled.

On an x86-64 Linux build host, install Zig 0.15.2, Python 3, GNU
binutils, tar and zip. The ARM builds use Bootlin's 2024.05-1 musl GCC
toolchains for [ARMv5 EABI](https://toolchains.bootlin.com/downloads/releases/toolchains/armv5-eabi/tarballs/armv5-eabi--musl--stable-2024.05-1.tar.xz)
and [AArch64](https://toolchains.bootlin.com/downloads/releases/toolchains/aarch64/tarballs/aarch64--musl--stable-2024.05-1.tar.xz).

    ./release.sh v1.0.1-rampage.3

The script builds and inspects all four archives and runs a loopback
SOCKS5 smoke test for Linux x86-64. Output goes to `dist/`. Set `ZIG`,
`ARM_CC` and `AARCH64_CC` to the compiler paths if `zig`,
`arm-buildroot-linux-musleabi-gcc` or `aarch64-buildroot-linux-musl-gcc`
are outside `PATH`.

Push a new version tag to run the GitHub Actions release workflow.
It runs the ARM tests under QEMU and the Windows test on a Windows
runner before publishing. Pushing a change to `release-version` on
`master` also runs the workflow for the version in that file.

To publish manually from a clean checkout of a commit already pushed
to GitHub, authenticate `gh` with repository write access and run:

    ./release.sh v1.0.1-rampage.3 --publish
