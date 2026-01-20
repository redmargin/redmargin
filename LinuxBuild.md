# Building Redmargin Server for Linux

## Prerequisites

### On Linux Host
Ensure basic build tools are installed:
```bash
sudo apt-get update && sudo apt-get install -y build-essential binutils-gold libcurl4-openssl-dev zlib1g-dev
```

### On macOS (Cross-compilation)
Install the Swift Static Linux SDK matching your toolchain.

## Building Remotely (Manual)

1. **Copy source code:**
   ```bash
   rsync -avz --exclude '.build' --exclude '.git' . user@host:~/redmargin-build/
   ```

2. **Run build script:**
   Save this as `build.sh` on the remote server and run it:
   ```bash
   #!/bin/bash
   # Download Swift if needed (example for Ubuntu 22.04)
   if [ ! -d "swift-6.0.2-RELEASE-ubuntu22.04" ]; then
       wget https://download.swift.org/swift-6.0.2-release/ubuntu2204/swift-6.0.2-RELEASE/swift-6.0.2-RELEASE-ubuntu22.04.tar.gz
       tar xzf swift-6.0.2-RELEASE-ubuntu22.04.tar.gz
   fi
   
   export PATH=$PWD/swift-6.0.2-RELEASE-ubuntu22.04/usr/bin:$PATH
   
   swift build -c release --product redmargin-server
   ```

3. **Retrieve binary:**
   The binary will be at `.build/release/redmargin-server`.
