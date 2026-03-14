# Stage 1: Build the native binary
FROM dart:stable AS build

WORKDIR /app
# Copy the entire workspace context so the build can see /packages/shared_models
COPY . .

RUN dart pub get
RUN dart compile exe bin/server.dart -o bin/server

# Stage 2: Create the runtime image
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/apps/server/bin/server /app/bin/server

# Start the server
EXPOSE 8080
CMD ["/app/bin/server"]