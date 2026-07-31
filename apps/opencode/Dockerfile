FROM node:22-bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends git ca-certificates \
  && rm -rf /var/lib/apt/lists/* \
  && printf '#!/bin/sh\nexit 0\n' > /usr/local/bin/xdg-open \
  && chmod +x /usr/local/bin/xdg-open

USER node
WORKDIR /home/wmichelin/code/homelab
