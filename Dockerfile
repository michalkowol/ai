ARG BASE_IMAGE=eclipse-temurin:25
FROM ${BASE_IMAGE}

RUN apt-get update && apt-get install -y curl git docker.io jq python3 python3-pip python3-venv sudo \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p -m 755 /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

RUN id ubuntu >/dev/null 2>&1 \
    || (userdel -r node 2>/dev/null || true; useradd -m -u 1000 -s /bin/bash ubuntu)

RUN echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu \
    && chmod 0440 /etc/sudoers.d/ubuntu

USER ubuntu

RUN curl https://cursor.com/install -fsS | bash
RUN curl -fsSL https://claude.ai/install.sh | bash

ENV PATH="/home/ubuntu/.local/bin:$PATH"
ENV TESTCONTAINERS_HOST_OVERRIDE=host.docker.internal

RUN echo 'echo -e "\\nTo run Claude with skipped permissions, type: \\033[1;32mclaude --dangerously-skip-permissions\\033[0m"' >> /home/ubuntu/.bashrc
RUN echo 'echo -e "To run the Cursor, type: \\033[1;32mcursor-agent --force --model gpt-5.3-codex-high\\033[0m"' >> /home/ubuntu/.bashrc
RUN echo 'echo -e "To run the Claude, type: \\033[1;32mclaude --enable-auto-mode\\033[0m\\n"' >> /home/ubuntu/.bashrc

RUN echo 'claude --enable-auto-mode' >> /home/ubuntu/.bash_history \
    && echo 'cursor-agent --force --model gpt-5.3-codex-high' >> /home/ubuntu/.bash_history \
    && echo 'claude --dangerously-skip-permissions' >> /home/ubuntu/.bash_history

WORKDIR /workspace
CMD ["bash"]
