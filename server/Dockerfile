# Build: AOT-compiled picpos_cloud on a minimal runtime image.
# The shared rules package (path dependency ../packages/picpos_rules) comes in
# through the named build context `picpos_rules`:
#   docker build --build-context picpos_rules=packages/picpos_rules -t picpos-cloud-test-api server
# or, in docker compose, `additional_contexts: { picpos_rules: ../packages/picpos_rules }`.
FROM dart:stable AS build
WORKDIR /src/server
COPY --from=picpos_rules pubspec.yaml /src/packages/picpos_rules/pubspec.yaml
COPY --from=picpos_rules lib /src/packages/picpos_rules/lib
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
