# syntax=docker/dockerfile:1

FROM debian:bookworm-slim AS web
ARG FLUTTER_VERSION=3.47.2
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils zip \
    && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git /opt/flutter \
    && git config --global --add safe.directory /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}"
RUN flutter config --no-analytics --enable-web && flutter precache --web
WORKDIR /src
COPY pubspec.yaml pubspec.lock ./
COPY packages/anki_core packages/anki_core
COPY server/pubspec.yaml server/
RUN flutter pub get
COPY . .
RUN flutter build web --release

FROM dart:3.13.2 AS server
WORKDIR /src
COPY packages/anki_core packages/anki_core
COPY server server
WORKDIR /src/server
RUN dart pub get && dart compile exe bin/server.dart -o /server

FROM scratch
COPY --from=server /runtime/ /
COPY --from=server /server /server
COPY --from=web /src/build/web /web
ENV PORT=8080 WEB_ROOT=/web
EXPOSE 8080
USER 65534:65534
ENTRYPOINT ["/server"]
