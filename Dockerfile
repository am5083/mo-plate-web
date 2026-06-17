# ─── build stage ──────────────────────────────────────────────────────────
FROM ocaml/opam:debian-12-ocaml-5.2 AS build

# System libs the OCaml deps need to compile: gmp for zarith/mirage-crypto,
# pkg-config for discovery.
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgmp-dev pkg-config && rm -rf /var/lib/apt/lists/*
USER opam

WORKDIR /app
COPY --chown=opam:opam dune-project ./
COPY --chown=opam:opam server ./server

# No opam package metadata in this repo (it's a vendored subset), so install the
# server's transitive deps explicitly.
RUN opam update && opam install -y dune cohttp-eio eio_main tls-eio ca-certs \
      mirage-crypto-rng-eio lambdasoup uri yojson
RUN eval $(opam env) && dune build server/main.exe

# ─── runtime stage ────────────────────────────────────────────────────────
FROM debian:12-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates libgmp10 && rm -rf /var/lib/apt/lists/*

# debian-slim ships without /etc/nsswitch.conf, so glibc's getaddrinfo never
# consults DNS and hostname resolution returns empty ("failed to resolve
# hostname"). Restore the normal resolution order.
RUN printf 'hosts: files dns\n' > /etc/nsswitch.conf

COPY --from=build /app/_build/default/server/main.exe /usr/local/bin/mo-plate-server

ENV PORT=8080
EXPOSE 8080
CMD ["mo-plate-server"]
