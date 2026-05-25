# Build the native server binary for Cloud Run.
#
# Flutter web is no longer bundled here — it's served by Firebase Hosting at
# votasqueue.web.app (and votasq.quikchange.net which CNAMEs to it), with a
# /api/** rewrite proxying back to this Cloud Run service same-origin. See
# .github/workflows/firebase-hosting-merge.yml for the web deploy pipeline.

FROM dart:stable AS build

WORKDIR /app

# Copy server and all workspace packages (not the Flutter client).
COPY pubspec.yaml pubspec.lock ./
COPY apps/server/ apps/server/
COPY packages/ packages/

# Remove the Flutter client and its iOS-only MLKit deps from the workspace
# so dart pub get succeeds without resolving Flutter SDK dependencies.
RUN sed -i -e '/apps\/client/d' -e '/google_mlkit/d' pubspec.yaml

# Generate the Dart Frog production server and compile it
RUN dart pub global activate dart_frog_cli
WORKDIR /app/apps/server
RUN dart pub get
RUN dart_frog build

WORKDIR /app/apps/server/build
RUN dart pub get
RUN dart compile exe bin/server.dart -o bin/server

# Runtime image
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/apps/server/build/bin/server /app/bin/server

WORKDIR /app
EXPOSE 8080
CMD ["/app/bin/server"]
