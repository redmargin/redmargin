# Building Redmargin Server for Linux

## Prerequisites

### On Linux Host

Ensure basic build tools are installed:

```bash
sudo apt-get update && sudo apt-get install -y build-essential binutils-gold libcurl4-openssl-dev zlib1g-dev
```

### On macOS (Cross-compilation)

Install the Swift Static Linux SDK matching your toolchain.

## Building Remotely

Use the checked-in build scripts. `resources/scripts/build-linux.sh` syncs the repository to the `devtest` SSH host, runs `resources/scripts/build-remote.sh` there, and copies the resulting binary back to `resources/servers/redmargin-server-x86_64-linux`.

```bash
./resources/scripts/build-linux.sh
```

The app build script also invokes the Linux build automatically when the bundled Linux server binary is missing or older than files under `Server/` or `src/Core/`:

```bash
./resources/scripts/build.sh
```
