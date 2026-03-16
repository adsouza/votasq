# Stage 1: Build the Flutter web client
FROM ghcr.io/cirruslabs/flutter:stable AS flutter-build

WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
COPY apps/client/ apps/client/
COPY packages/shared/ packages/shared/

# Remove the server from the workspace so flutter pub get succeeds
RUN sed -i '/apps\/server/d' pubspec.yaml

WORKDIR /app/apps/client
RUN flutter pub get
RUN flutter build web --release --target lib/main_production.dart --dart-define=SERVER_URL=

# Stage 2: Build the native server binary
FROM dart:stable AS build

WORKDIR /app

# Copy only the server and shared packages (not the Flutter client)
COPY pubspec.yaml pubspec.lock ./
COPY apps/server/ apps/server/
COPY packages/shared/ packages/shared/

# Remove the Flutter client from the workspace so dart pub get succeeds
RUN sed -i '/apps\/client/d' pubspec.yaml

# Copy the web build output into the server's public directory
COPY --from=flutter-build /app/apps/client/build/web/ apps/server/public/

# Generate the Dart Frog production server and compile it
RUN dart pub global activate dart_frog_cli
WORKDIR /app/apps/server
RUN dart pub get
RUN dart_frog build

WORKDIR /app/apps/server/build
RUN dart pub get
RUN dart compile exe bin/server.dart -o bin/server

# Stage 3: Create the runtime image
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/apps/server/build/bin/server /app/bin/server
COPY --from=build /app/apps/server/build/public/ /app/public/

WORKDIR /app
EXPOSE 8080
CMD ["/app/bin/server"]
