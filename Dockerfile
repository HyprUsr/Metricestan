# Build stage: compile the Dart application to a native binary
FROM --platform=$BUILDPLATFORM dart:stable AS build

WORKDIR /src

COPY pubspec.yaml pubspec.lock* ./
RUN dart pub cache clean
RUN dart pub cache repair
RUN dart pub get

COPY . .
RUN dart pub get --offline

RUN mkdir -p /out
RUN dart compile exe bin/app.dart -o /out/app --target-os=linux --target-arch=x64

# Lightweight runtime stage using distroless base image
FROM gcr.io/distroless/cc AS runtime

WORKDIR /

COPY --from=build /out/app /app

USER nonroot

ENTRYPOINT ["/app"]
