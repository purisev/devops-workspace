ARG DEBIAN_BASE=trixie
FROM debian:${DEBIAN_BASE}-slim

# --- Version pins (override at build time with --build-arg) ----------------
ARG DEBIAN_BASE=trixie
ARG PYTHON_VERSION=3.13
ARG POSTGRESQL_CLIENT_VERSION=18
ARG BAT_VERSION=0.26.1
ARG KANIKO_VERSION=v1.24.0
ARG VAULT_VERSION=1.20.4
ARG TERRAFORM_VERSION=1.12.1
ARG MONGODB_VERSION=8.0
# ---------------------------------------------------------------------------

# Update and install base packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    sudo \
    unzip \
    wget && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install locales
RUN apt-get update && \
    apt-get install -y --no-install-recommends locales && \
    sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Set environment variables
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    DOCKER_HOST=unix:///var/run/docker.sock

# Install core development tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ansible \
    bash-completion \
    dos2unix \
    git \
    git-lfs \
    jq \
    less \
    nano \
    openssh-server \
    openssl \
    procps \
    python3-pip \
    python3-venv \
    python${PYTHON_VERSION} \
    rsync \
    tmux \
    vim \
    zsh && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install network and monitoring tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    dnsutils \
    htop \
    httpie \
    iftop \
    iputils-ping \
    mtr \
    netcat-openbsd \
    nfs-common \
    nmap \
    sysstat \
    traceroute && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install database clients
RUN install -d /usr/share/postgresql-common/pgdg && \
    curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc && \
    echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt ${DEBIAN_BASE}-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    default-mysql-client \
    postgresql-client-${POSTGRESQL_CLIENT_VERSION} \
    redis-tools && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install fd-find and create symlink
RUN apt-get update && \
    apt-get install -y --no-install-recommends fd-find && \
    ln -sf "$(which fdfind)" /usr/local/bin/fd && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install utilities not available via apt
RUN mkdir -p /usr/local/bin && \
    echo "Installing yq for YAML processing" && \
    wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_$(dpkg --print-architecture) && \
    chmod +x /usr/local/bin/yq && \
    echo "Installing fzf interactive search" && \
    git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf && \
    ~/.fzf/install --all && \
    echo "Installing bat - improved cat" && \
    if ! command -v bat &> /dev/null; then \
        wget -qO /tmp/bat.deb https://github.com/sharkdp/bat/releases/download/v${BAT_VERSION}/bat_${BAT_VERSION}_$(dpkg --print-architecture).deb && \
        dpkg -i /tmp/bat.deb && \
        rm /tmp/bat.deb; \
    fi && \
    # Clean git cache
    rm -rf ~/.fzf/.git

# Install Docker and Docker Buildx
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io docker-compose-plugin && \
    echo "Installing Docker Buildx" && \
    mkdir -p ~/.docker/cli-plugins && \
    BUILDX_VERSION=$(curl -s https://api.github.com/repos/docker/buildx/releases/latest | grep tag_name | cut -d '"' -f 4) && \
    curl -fsSL "https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.linux-$(dpkg --print-architecture)" -o ~/.docker/cli-plugins/docker-buildx && \
    chmod +x ~/.docker/cli-plugins/docker-buildx && \
    echo "Installing Kaniko for container builds" && \
    curl -Lo /usr/local/bin/executor "https://github.com/GoogleContainerTools/kaniko/releases/download/${KANIKO_VERSION}/executor-linux-$(dpkg --print-architecture)" && \
    chmod +x /usr/local/bin/executor && \
    ln -s /usr/local/bin/executor /usr/local/bin/kaniko && \
    echo "Installing Crane for registry operations" && \
    CRANE_VERSION=$(curl -s https://api.github.com/repos/google/go-containerregistry/releases/latest | grep tag_name | cut -d '"' -f 4) && \
    CRANE_ARCH=$(dpkg --print-architecture | sed 's/amd64/x86_64/') && \
    curl -fsSL "https://github.com/google/go-containerregistry/releases/download/${CRANE_VERSION}/go-containerregistry_Linux_${CRANE_ARCH}.tar.gz" | tar -xz -C /usr/local/bin crane && \
    chmod +x /usr/local/bin/crane && \
    # Clean apt cache and temp files
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install HashiCorp tools (Terraform, Vault, Terragrunt, Terramate)
RUN echo "Installing Vault ${VAULT_VERSION}" && \
    wget -O /tmp/vault.zip https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_$(dpkg --print-architecture).zip && \
    unzip -o /tmp/vault.zip -d /usr/local/bin/ && \
    chmod +x /usr/local/bin/vault && \
    rm /tmp/vault.zip && \
    echo "Installing Terraform ${TERRAFORM_VERSION}" && \
    wget -O /tmp/terraform.zip https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_$(dpkg --print-architecture).zip && \
    unzip -o /tmp/terraform.zip -d /usr/local/bin/ && \
    chmod +x /usr/local/bin/terraform && \
    rm /tmp/terraform.zip && \
    echo "Installing Terragrunt" && \
    curl -o /usr/local/bin/terragrunt -fsSL "https://github.com/gruntwork-io/terragrunt/releases/latest/download/terragrunt_linux_$(dpkg --print-architecture)" && \
    chmod +x /usr/local/bin/terragrunt && \
    echo "Installing Terramate" && \
    TERRAMATE_VERSION=$(curl -s https://api.github.com/repos/terramate-io/terramate/releases/latest | grep tag_name | cut -d '"' -f 4 | sed 's/v//') && \
    TM_ARCH=$(dpkg --print-architecture | sed 's/amd64/x86_64/') && \
    wget -qO terramate.tar.gz "https://github.com/terramate-io/terramate/releases/download/v${TERRAMATE_VERSION}/terramate_${TERRAMATE_VERSION}_Linux_${TM_ARCH}.tar.gz" && \
    tar -xzf terramate.tar.gz -C /tmp && \
    mv /tmp/terramate /usr/local/bin/ && \
    chmod +x /usr/local/bin/terramate && \
    rm -f terramate.tar.gz && \
    # Clean apt cache and temp files
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install cloud tools (AWS, Yandex)
RUN echo "Installing AWS CLI" && \
    AWS_ARCH=$(dpkg --print-architecture | sed 's/amd64/x86_64/;s/arm64/aarch64/') && \
    curl "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o "awscliv2.zip" && \
    unzip -q awscliv2.zip && \
    ./aws/install && \
    rm -rf aws awscliv2.zip && \
    echo "Installing Yandex CLI" && \
    curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh | bash && \
    # Clean temp files
    rm -rf /tmp/* /var/tmp/*

# Install Kubernetes tools (kubectl, helm, k9s, argo, flux)
RUN echo "Installing kubectl" && \
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/$(dpkg --print-architecture)/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/ && \
    echo "Installing Helm" && \
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && \
    chmod +x get_helm.sh && \
    ./get_helm.sh && \
    rm get_helm.sh && \
    echo "Installing chart-testing (ct)" && \
    CT_VERSION=$(curl -s https://api.github.com/repos/helm/chart-testing/releases/latest | jq -r '.tag_name') && \
    CT_VERSION_NUM=$(echo "${CT_VERSION}" | sed 's/^v//') && \
    curl -fsSL "https://github.com/helm/chart-testing/releases/download/${CT_VERSION}/chart-testing_${CT_VERSION_NUM}_linux_$(dpkg --print-architecture).tar.gz" | tar -xz -C /tmp ct && \
    mv /tmp/ct /usr/local/bin/ && \
    chmod +x /usr/local/bin/ct && \
    echo "Installing k9s" && \
    curl -fsSL https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_$(dpkg --print-architecture).tar.gz | tar -xz -C /usr/local/bin k9s && \
    chmod +x /usr/local/bin/k9s && \
    echo "Installing kubectx and kubens" && \
    git clone --depth 1 https://github.com/ahmetb/kubectx /opt/kubectx && \
    ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx && \
    ln -s /opt/kubectx/kubens /usr/local/bin/kubens && \
    rm -rf /opt/kubectx/.git && \
    echo "Installing Argo CLI" && \
    curl -sSL -o /usr/local/bin/argo https://github.com/argoproj/argo-workflows/releases/latest/download/argo-linux-$(dpkg --print-architecture) && \
    chmod +x /usr/local/bin/argo && \
    echo "Installing Flux CLI" && \
    curl -s https://fluxcd.io/install.sh | bash && \
    # Clean temp files
    rm -rf /tmp/* /var/tmp/*

# Install GitHub and GitLab CLI
RUN echo "Installing GitHub CLI" && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && \
    apt-get install -y --no-install-recommends gh && \
    echo "Installing GitLab CLI" && \
    curl -L https://gitlab-org.gitlab.io/cli/gitlab_glab_linux_$(dpkg --print-architecture) -o /usr/local/bin/glab && \
    chmod +x /usr/local/bin/glab && \
    echo "Installing MongoDB Shell" && \
    curl -fsSL https://pgp.mongodb.com/server-${MONGODB_VERSION}.asc | gpg -o /usr/share/keyrings/mongodb-server-${MONGODB_VERSION}.gpg --dearmor && \
    echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-${MONGODB_VERSION}.gpg] http://repo.mongodb.org/apt/debian bookworm/mongodb-org/${MONGODB_VERSION} main" | tee /etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}.list > /dev/null && \
    apt-get update && \
    apt-get install -y --no-install-recommends mongodb-mongosh && \
    # Clean apt cache and temp files
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Set up workspace and Python virtual environment
WORKDIR /workspace
RUN mkdir -p /workspace/.python-envs && \
    python3 -m venv /workspace/.python-envs/toolset && \
    . /workspace/.python-envs/toolset/bin/activate && \
    pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir ansible-lint virtualenv pipenv python-openstackclient openstacksdk hvac yamale && \
    # Clean pip cache
    rm -rf ~/.cache/pip

# Install Ansible Collections
RUN ansible-galaxy collection install community.docker -p /usr/share/ansible/collections --force && \
    ansible-galaxy collection install ansible.posix -p /usr/share/ansible/collections --force && \
    ansible-galaxy collection install community.hashi_vault -p /usr/share/ansible/collections --force && \
    ansible-galaxy collection install community.general -p /usr/share/ansible/collections --force && \
    ansible-galaxy collection install community.crypto -p /usr/share/ansible/collections --force && \
    ansible-galaxy collection install freeipa.ansible_freeipa -p /usr/share/ansible/collections --force

# Set up auto-activation and autocompletion
RUN echo "Setting up Python venv autoactivation" && \
    echo '\n# Automatically activate Python venv\nif [ -f /workspace/.python-envs/toolset/bin/activate ]; then\n    . /workspace/.python-envs/toolset/bin/activate\nfi' >> /etc/bash.bashrc && \
    echo '\n# Automatically activate Python venv\nif [ -f /workspace/.python-envs/toolset/bin/activate ]; then\n    . /workspace/.python-envs/toolset/bin/activate\nfi' >> /etc/skel/.bashrc && \
    echo '\n# Automatically activate Python venv\nif [ -f /workspace/.python-envs/toolset/bin/activate ]; then\n    . /workspace/.python-envs/toolset/bin/activate\nfi' >> /root/.bashrc && \
    echo '\n# Automatically source common commands\nif [ -f ~/.bashrc_common ]; then\n    . ~/.bashrc_common\nfi' >> /root/.bashrc && \
    echo '\n# Automatically source custom commands\nif [ -f ~/.bashrc_custom ]; then\n    . ~/.bashrc_custom\nfi' >> /root/.bashrc && \
    echo "Setting up shell autocompletion" && \
    echo '\n# Set up autocompletion\nif [ -f /etc/bash_completion ] && ! shopt -oq posix; then\n    . /etc/bash_completion\nfi' >> /etc/bash.bashrc && \
    echo '\n# AWS CLI autocompletion\ncomplete -C "/usr/bin/aws_completer" aws' >> /etc/bash.bashrc && \
    echo "Setting up Terraform autocompletion" && \
    terraform -install-autocomplete || true

# Configure user and SSH
RUN echo "Creating devuser with sudo privileges" && \
    useradd -m -s /bin/bash devuser && \
    echo "devuser ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/devuser && \
    chmod 0440 /etc/sudoers.d/devuser && \
    echo '\n# Automatically activate Python venv\nif [ -f /workspace/.python-envs/toolset/bin/activate ]; then\n    . /workspace/.python-envs/toolset/bin/activate\nfi' >> /home/devuser/.bashrc && \
    echo "Setting up SSH server" && \
    mkdir -p /var/run/sshd && \
    echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config && \
    echo 'PermitRootLogin prohibit-password' >> /etc/ssh/sshd_config && \
    echo "Setting workspace permissions" && \
    chown -R devuser:devuser /workspace

# Expose ports and startup script
EXPOSE 22
RUN printf '#!/bin/bash\n\
# Optionally set SSH passwords via container environment variables:\n\
#   ROOT_PASSWORD    — enables password login for root (key auth is always available)\n\
#   DEVUSER_PASSWORD — sets password for devuser\n\
# If neither is set, only SSH key authentication works (keys from mounted ~/.ssh).\n\
[ -n "${ROOT_PASSWORD}" ]    && echo "root:${ROOT_PASSWORD}"       | chpasswd\n\
[ -n "${DEVUSER_PASSWORD}" ] && echo "devuser:${DEVUSER_PASSWORD}" | chpasswd\n\
service ssh start\n\
tail -f /dev/null\n' > /start.sh && chmod +x /start.sh

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD pgrep sshd > /dev/null || exit 1

CMD ["/start.sh"]
