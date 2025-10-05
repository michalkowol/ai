FROM eclipse-temurin:22
RUN apt-get update && apt-get install -y curl git
RUN curl https://cursor.com/install -fsS | bash
COPY cursor/ /root/.cursor/
COPY config/ /root/.config/
WORKDIR /cursor
ENV PATH="/root/.local/bin:$PATH"
RUN echo 'echo -e "To run the agent, type: \\033[1;32mcursor-agent --force\\033[0m"\n' >> /root/.bashrc
CMD ["bash"]
