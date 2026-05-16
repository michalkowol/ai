FROM eclipse-temurin:25

RUN apt-get update && apt-get install -y curl git docker.io \
    && rm -rf /var/lib/apt/lists/*

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
