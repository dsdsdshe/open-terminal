# Pin to a specific patch version for reproducible builds.
# To pick up security patches, bump this version and rebuild.
ARG PYTHON_VERSION=3.11
FROM python:${PYTHON_VERSION}

ARG RUNTIME_PIP_INDEX_URL=https://mirrors.tools.huawei.com/pypi/simple
ARG RUNTIME_PIP_TRUSTED_HOST=mirrors.tools.huawei.com

RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core utilities
    coreutils findutils grep sed gawk diffutils patch \
    less file tree bc man-db \
    # Networking
    curl wget net-tools iputils-ping dnsutils netcat-openbsd socat telnet \
    openssh-client rsync \
    # Editors
    vim nano \
    # Version control
    git \
    # Build tools
    build-essential cmake make \
    # Scripting & languages
    perl ruby-full lua5.4 \
    # Data processing
    jq xmlstarlet sqlite3 \
    # Media & documents
    ffmpeg pandoc imagemagick texlive-latex-base \
    # Compression
    zip unzip tar gzip bzip2 xz-utils zstd p7zip-full \
    # System
    procps htop lsof strace sysstat \
    sudo tmux screen tini iptables ipset dnsmasq \
    ca-certificates gnupg apt-transport-https \
    # Capabilities (needed for setcap on Python binary)
    libcap2-bin \
    && rm -rf /var/lib/apt/lists/*

# Node.js (LTS)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Preinstall Node packages commonly needed in terminal sessions.
RUN npm install -g pptxgenjs

ENV NODE_PATH=/usr/lib/node_modules

# Preconfigure npm for internal-network deployments.
RUN { \
        printf 'strict-ssl=false\n'; \
        printf 'registry=https://mirrors.tools.huawei.com/npm/\n'; \
    } > /etc/npmrc \
    && npm cache clean --force

# Docker CLI + Compose + Buildx (mount socket at runtime for access)
RUN curl -fsSL https://get.docker.com | sh

# Uncomment to apply security patches beyond what the base image provides.
# Not recommended for reproducible builds; prefer bumping the base image tag.
# RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*


WORKDIR /app

RUN pip install --no-cache-dir \
    numpy pandas scipy scikit-learn \
    matplotlib seaborn plotly \
    jupyter ipython \
    requests beautifulsoup4 lxml \
    sqlalchemy psycopg2-binary \
    pyyaml toml jsonlines \
    tqdm rich \
    openpyxl weasyprint \
    python-docx python-pptx pypdf csvkit \
    mindquantum

COPY . .
# setcap MUST run in the same layer as the Python binary to avoid
# overlay2 copy-up corruption of libpython3.12.so ("file too short").
RUN pip install --no-cache-dir . \
    && setcap cap_setgid+ep $(readlink -f $(which python3))

# Build on public networks, but default runtime package managers to the
# internal Huawei mirrors once the image is assembled.
RUN if [ -n "$RUNTIME_PIP_INDEX_URL" ]; then \
        { \
            printf '[global]\n'; \
            printf 'index-url = %s\n' "$RUNTIME_PIP_INDEX_URL"; \
            if [ -n "$RUNTIME_PIP_TRUSTED_HOST" ]; then \
                printf 'trusted-host = %s\n' "$RUNTIME_PIP_TRUSTED_HOST"; \
            fi; \
        } > /etc/pip.conf; \
    fi \
    && if [ -f /etc/apt/sources.list ]; then \
        sed -i 's|http://deb.debian.org/debian|https://mirrors.tools.huawei.com/debian|g; s|http://security.debian.org/debian-security|https://mirrors.tools.huawei.com/debian-security|g; s|http://deb.debian.org/debian-security|https://mirrors.tools.huawei.com/debian-security|g; s|https://deb.debian.org/debian|https://mirrors.tools.huawei.com/debian|g; s|https://security.debian.org/debian-security|https://mirrors.tools.huawei.com/debian-security|g; s|https://deb.debian.org/debian-security|https://mirrors.tools.huawei.com/debian-security|g' /etc/apt/sources.list; \
    fi \
    && if [ -d /etc/apt/sources.list.d ]; then \
        find /etc/apt/sources.list.d -type f \( -name '*.list' -o -name '*.sources' \) -exec sed -i 's|http://deb.debian.org/debian|https://mirrors.tools.huawei.com/debian|g; s|http://security.debian.org/debian-security|https://mirrors.tools.huawei.com/debian-security|g; s|http://deb.debian.org/debian-security|https://mirrors.tools.huawei.com/debian-security|g; s|https://deb.debian.org/debian|https://mirrors.tools.huawei.com/debian|g; s|https://security.debian.org/debian-security|https://mirrors.tools.huawei.com/debian-security|g; s|https://deb.debian.org/debian-security|https://mirrors.tools.huawei.com/debian-security|g' {} +; \
    fi

RUN useradd -m -s /bin/bash user && echo 'user ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

USER user
ENV SHELL=/bin/bash
ENV PATH="/home/user/.local/bin:${PATH}"
WORKDIR /home/user

EXPOSE 8000

COPY entrypoint.sh /app/entrypoint.sh

ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
CMD ["run"]
