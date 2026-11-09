FROM ubuntu:24.04

RUN apt-get update && apt-get install -y ca-certificates curl git docker.io gh libatomic1 sudo unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN id ubuntu >/dev/null 2>&1 || useradd -m -u 1000 -s /bin/bash ubuntu

RUN echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu \
    && chmod 0440 /etc/sudoers.d/ubuntu

USER ubuntu

ENV PATH="/home/ubuntu/.local/bin:/home/ubuntu/.local/share/mise/shims:$PATH"

RUN curl -fsSL https://mise.run | sh
RUN mise install node@lts/jod node@lts/lithium python@3.14 java@temurin-11 java@temurin-21 java@temurin-25 \
    && mise use -g node@lts/lithium python@3.14 java@temurin-25 \
    && mise reshim
RUN echo 'eval "$(mise activate bash)"' >> /home/ubuntu/.bashrc

RUN curl https://cursor.com/install -fsS | bash
RUN curl -fsSL https://claude.ai/install.sh | bash

ENV TESTCONTAINERS_HOST_OVERRIDE=host.docker.internal

RUN echo 'echo -e "\\nTo run Claude with skipped permissions, type: \\033[1;32mclaude --dangerously-skip-permissions\\033[0m"' >> /home/ubuntu/.bashrc
RUN echo 'echo -e "To run the Cursor, type: \\033[1;32mcursor-agent --force --model gpt-5.3-codex-high\\033[0m"' >> /home/ubuntu/.bashrc
RUN echo 'echo -e "To run the Claude, type: \\033[1;32mclaude --enable-auto-mode\\033[0m\\n"' >> /home/ubuntu/.bashrc

RUN echo 'claude --enable-auto-mode' >> /home/ubuntu/.bash_history \
    && echo 'cursor-agent --force --model gpt-5.3-codex-high' >> /home/ubuntu/.bash_history \
    && echo 'claude --dangerously-skip-permissions' >> /home/ubuntu/.bash_history

WORKDIR /workspace
CMD ["bash"]
