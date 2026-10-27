# syntax=docker/dockerfile:1

########## Stage 1 — build the WASM + web bundle ##########
FROM rust:nightly-slim-bookworm AS build

RUN apt-get update \
&& apt-get install -y --no-install-recommends curl ca-certificates gnupg \
&& rm -rf /var/lib/apt/lists/*

# Node 20 — webpack + @wasm-tool/wasm-pack-plugin
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
&& apt-get install -y --no-install-recommends nodejs \
&& rm -rf /var/lib/apt/lists/*

# wasm32 target + rust-src (required by -Zbuild-std) + pinned wasm-pack
RUN rustup target add wasm32-unknown-unknown \
&& rustup component add rust-src \
&& curl -fsSL -o /tmp/wp.tar.gz \
https://github.com/rustwasm/wasm-pack/releases/download/v0.15.0/wasm-pack-v0.15.0-x86_64-unknown-linux-musl.tar.gz \
&& tar -xzf /tmp/wp.tar.gz -C /tmp \
&& mv /tmp/wasm-pack-v0.15.0-x86_64-unknown-linux-musl/wasm-pack /usr/local/bin/ \
&& rm -rf /tmp/wp.tar.gz /tmp/wasm-pack-*

WORKDIR /app
COPY . .

# webpack reads BUILD_MODE; without this you ship an unminified dev build
ENV BUILD_MODE=production
RUN cd frontend/web && npm install && npm run build

########## Stage 2 — serve ##########
FROM nginx:stable-alpine

COPY <<'EOF' /etc/nginx/conf.d/default.conf
server {
listen 8080;
server_name _;

root /usr/share/nginx/html;
index index.html;

# Mandatory: the emulator uses SharedArrayBuffer, which browsers only
# expose when the page is cross-origin isolated.
add_header Cross-Origin-Opener-Policy "same-origin" always;
add_header Cross-Origin-Embedder-Policy "require-corp" always;

gzip on;
gzip_types application/wasm application/javascript text/css application/json;

location /pkg/ {
expires 1y;
}

location / {
try_files $uri $uri/ /index.html;
}
}
EOF

COPY --from=build /app/frontend/web/dist /usr/share/nginx/html
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
