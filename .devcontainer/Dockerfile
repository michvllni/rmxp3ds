# Dev container for xp3ds: devkitARM + libctru/citro3d, host Ruby for the converter
# and for cross-compiling CRuby (needs a matching "baseruby"), plus 3DS packaging tools.
FROM devkitpro/devkitarm:latest

ENV DEBIAN_FRONTEND=noninteractive

# Must match the Ruby version the runtime embeds (check mkxp-z), so ISeq binaries load.
ARG RUBY_VERSION=3.1.6
# Packaging tools — check the release pages for current versions/asset names.
ARG MAKEROM_URL=https://github.com/3DSGuy/Project_CTR/releases/download/makerom-v0.18.4/makerom-v0.18.4-ubuntu_x86_64.zip
ARG BANNERTOOL_URL=https://github.com/Epicpkmn11/bannertool/releases/latest/download/bannertool.zip
# Azahar AppImage (check the releases page for the current asset name; pin a version for reproducibility)
ARG AZAHAR_URL=https://github.com/azahar-emu/azahar/releases/latest/download/azahar.AppImage

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential git curl ca-certificates unzip pkg-config \
        autoconf automake libtool bison \
        libyaml-dev libssl-dev libreadline-dev zlib1g-dev libffi-dev libgdbm-dev \
        cmake ninja-build meson \
        python3 python3-pip \
        ffmpeg imagemagick \
        gdb-multiarch \
        xvfb xauth x11-utils \
        libgl1-mesa-dri libegl1 mesa-vulkan-drivers \
        libxkbcommon-x11-0 libxcb-cursor0 libxcb-icccm4 libxcb-image0 \
        libxcb-keysyms1 libxcb-randr0 libxcb-render-util0 libxcb-xinerama0 \
        libxcb-xkb1 libfontconfig1 libdbus-1-3 \
    && rm -rf /var/lib/apt/lists/*

# 3DS libraries. Portlibs that don't exist under that name only warn.
RUN dkp-pacman -Syu --noconfirm \
    && dkp-pacman -S --noconfirm --needed 3ds-dev \
    && for p in 3ds-zlib 3ds-libpng 3ds-freetype 3ds-libogg 3ds-libvorbisidec 3ds-bzip2; do \
         dkp-pacman -S --noconfirm --needed "$p" || echo "WARN: package $p not available"; \
       done \
    && dkp-pacman -Scc --noconfirm

# Host Ruby (converter + baseruby for the CRuby cross build)
RUN git clone --depth 1 https://github.com/rbenv/ruby-build.git /tmp/ruby-build \
    && /tmp/ruby-build/install.sh \
    && rm -rf /tmp/ruby-build \
    && ruby-build "${RUBY_VERSION}" /opt/ruby
ENV PATH=/opt/ruby/bin:${PATH}

# makerom + bannertool for CIA builds (forwarders, release CIA)
RUN mkdir -p /tmp/tools && cd /tmp/tools \
    && curl -fL -o makerom.zip "${MAKEROM_URL}" && unzip -o makerom.zip \
    && curl -fL -o bannertool.zip "${BANNERTOOL_URL}" && unzip -o bannertool.zip \
    && install -m 755 "$(find . -type f -name makerom | head -n1)" /usr/local/bin/makerom \
    && install -m 755 "$(find . -type f -path '*linux-x86_64*' -name bannertool | head -n1)" /usr/local/bin/bannertool \
    && cd / && rm -rf /tmp/tools

# Azahar, headless: AppImage extracted (no FUSE in containers), run on a virtual X display.
# Rendering uses /dev/dri if passed in, otherwise Mesa software rendering (llvmpipe/lavapipe).
RUN cd /opt && curl -fL -o azahar.AppImage "${AZAHAR_URL}" \
    && chmod +x azahar.AppImage && ./azahar.AppImage --appimage-extract >/dev/null \
    && mv squashfs-root azahar && rm azahar.AppImage
COPY azahar-headless.sh /usr/local/bin/azahar-headless
RUN chmod +x /usr/local/bin/azahar-headless

ENV DEVKITPRO=/opt/devkitpro \
    DEVKITARM=/opt/devkitpro/devkitARM \
    PATH=/opt/devkitpro/tools/bin:/opt/devkitpro/devkitARM/bin:${PATH}

# Sanity check: fail the build early if a key tool is missing
RUN arm-none-eabi-gcc --version >/dev/null \
    && tex3ds --help >/dev/null 2>&1; \
    command -v 3dslink && command -v 3dsxtool && command -v makerom && command -v bannertool && ruby -v \
    && test -x /opt/azahar/AppRun

WORKDIR /workspaces/xp3ds
