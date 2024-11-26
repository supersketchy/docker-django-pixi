FROM node:20.6.1-bookworm-slim AS assets
LABEL maintainer="Nick Janetakis <nick.janetakis@gmail.com>"

WORKDIR /app/assets

ARG UID=1000
ARG GID=1000

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential \
  && rm -rf /var/lib/apt/lists/* /usr/share/doc /usr/share/man \
  && apt-get clean \
  && groupmod -g "${GID}" node && usermod -u "${UID}" -g "${GID}" node \
  && mkdir -p /node_modules && chown node:node -R /node_modules /app \
  && npm install -g pnpm

USER node

COPY --chown=node:node assets/package.json assets/*pnpm* ./

RUN pnpm install && pnpm store prune

ARG NODE_ENV="production"
ENV NODE_ENV="${NODE_ENV}" \
    PATH="${PATH}:/node_modules/.bin" \
    USER="node"

COPY --chown=node:node . ..

RUN if [ "${NODE_ENV}" != "development" ]; then \
  ../run pnpm build:js && ../run pnpm build:css; else mkdir -p /app/public; fi

CMD ["bash"]

###############################################################################

FROM ghcr.io/prefix-dev/pixi:latest AS app
LABEL maintainer="Nick Janetakis <nick.janetakis@gmail.com>"

WORKDIR /app

ARG UID=1000
ARG GID=1000

RUN groupadd -g "${GID}" python \
    && useradd --create-home --no-log-init -u "${UID}" -g "${GID}" python \
    && mkdir -p /public_collected public \
    && chown python:python -R /public_collected /app

USER python

COPY --from=assets /app/public /public
COPY --chown=python:python . .

RUN rm -rf /app/.pixi/ && pixi install --locked -e prod

ARG DEBUG="false"
ENV DEBUG="${DEBUG}" \
    PYTHONUNBUFFERED="true" \
    PYTHONPATH="." \
    PATH="${PATH}:/app/.pixi/envs/prod/bin" \
    USER="python"

WORKDIR /app/src

RUN if [ "${DEBUG}" = "false" ]; then \
  SECRET_KEY=dummyvalue python3 manage.py collectstatic --no-input; \
    else mkdir -p /app/public_collected; fi

EXPOSE 8000

CMD ["pixi", "run", "-e", "prod", "gunicorn", "-c", "python:config.gunicorn", "config.wsgi"]
