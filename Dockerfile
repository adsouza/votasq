# Stage 1: Build the native binary
FROM dart:stable AS build

WORKDIR /app
COPY . .

RUN dart pub get
RUN dart compile exe apps/server/bin/server.dart -o apps/server/bin/server

# Stage 2: Create the runtime image
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/apps/server/bin/server /app/bin/server

EXPOSE 8080
CMD ["/app/bin/server"]
