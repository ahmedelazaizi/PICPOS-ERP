# Build: AOT-compiled picpos_cloud on a minimal runtime image.
FROM dart:stable AS build
WORKDIR /src
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN mkdir -p /out && dart pub get --offline \
 && dart compile exe bin/server.dart -o /out/server \
 && dart compile exe bin/healthcheck.dart -o /out/healthcheck

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /out/server /app/server
COPY --from=build /out/healthcheck /app/healthcheck
EXPOSE 8080
ENTRYPOINT ["/app/server"]
