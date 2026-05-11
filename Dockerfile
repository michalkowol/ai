FROM eclipse-temurin:22

RUN apt-get update && apt-get install -y curl git \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /workspace && chown ubuntu:ubuntu /workspace

USER ubuntu

RUN curl https://cursor.com/install -fsS | bash
RUN curl -fsSL https://claude.ai/install.sh | bash

ENV PATH="/home/ubuntu/.local/bin:$PATH"

RUN echo 'echo -e "\\nTo run the Claude, type: \\033[1;32mclaude --enable-auto-mode\\033[0m"' >> /home/ubuntu/.bashrc
RUN echo 'echo -e "To run the Cursor, type: \\033[1;32mcursor-agent --force\\033[0m\\n"' >> /home/ubuntu/.bashrc

WORKDIR /workspace
CMD ["bash"]
