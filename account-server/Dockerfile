FROM rust:1-bookworm AS build
ENV CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse
RUN printf '[source.crates-io]\nreplace-with = "rsproxy-sparse"\n[source.rsproxy-sparse]\nregistry = "sparse+https://rsproxy.cn/index/"\n' > "$CARGO_HOME/config.toml"
WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY src ./src
RUN cargo build --release --locked

FROM debian:bookworm@sha256:268fb24c39bca92d326dd83ea3abebe4a3f7751c804ffef23bb6d857dd343ff8
COPY --from=build /app/target/release/rustdesk-account-server /usr/local/bin/account-server
ENV ACCOUNT_BIND=0.0.0.0:21114 \
    ACCOUNT_DB=/data/account.db
VOLUME ["/data"]
EXPOSE 21114
CMD ["account-server"]
