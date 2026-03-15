# Stage 1: Build the native binary
FROM dart:stable AS build

WORKDIR /app

# Copy only the server and shared packages (not the Flutter client)
COPY pubspec.yaml pubspec.lock ./
COPY apps/server/ apps/server/
COPY packages/shared/ packages/shared/

# Remove the Flutter client from the workspace so dart pub get succeeds
RUN sed -i '/apps\/client/d' pubspec.yaml

# Generate the Dart Frog production server and compile it
RUN dart pub global activate dart_frog_cli
WORKDIR /app/apps/server
RUN dart pub get
RUN dart pub global run dart_frog build

WORKDIR /app/apps/server/build
RUN dart pub get
RUN dart compile exe bin/server.dart -o bin/server

# Stage 2: Create the runtime image
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/apps/server/build/bin/server /app/bin/server

EXPOSE 8080
CMD ["/app/bin/server"]
