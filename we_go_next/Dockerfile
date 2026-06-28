# syntax=docker/dockerfile:1

ARG ELIXIR_IMAGE=elixir:1.19.5-otp-28-slim
ARG RUNNER_IMAGE=debian:bookworm-slim

FROM ${ELIXIR_IMAGE} AS builder

ARG ZIG_VERSION=0.15.2

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends build-essential ca-certificates curl git xz-utils \
  && curl -fsSL "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" -o /tmp/zig.tar.xz \
  && mkdir -p /opt/zig \
  && tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1 \
  && ln -s /opt/zig/zig /usr/local/bin/zig \
  && rm -f /tmp/zig.tar.xz \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod \
  ZIG_EXECUTABLE_PATH=/usr/local/bin/zig

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config config

RUN mix deps.get --only prod
RUN mix deps.compile

COPY assets assets
COPY lib lib
COPY priv priv

RUN mix assets.deploy
RUN mix compile
RUN mix release

FROM ${RUNNER_IMAGE} AS runner

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends ca-certificates libncurses6 libstdc++6 locales openssl \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && useradd --create-home --home-dir /home/app app

WORKDIR /app

ENV HOME=/home/app \
  LANG=C.UTF-8 \
  MIX_ENV=prod

COPY --from=builder --chown=app:app /app/_build/prod/rel/we_go_next ./
COPY --chown=app:app docker-entrypoint.sh /app/bin/docker-entrypoint

RUN chmod +x /app/bin/docker-entrypoint

USER app

ENTRYPOINT ["/app/bin/docker-entrypoint"]
CMD ["/app/bin/we_go_next", "start"]
