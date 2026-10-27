# syntax=docker/dockerfile:1

########## Stage 1 — build the WASM + web bundle ##########
FROM rust:slim-bookworm AS build

# Tools needed to compile
RUN apt-get update && apt-get install -y --no-install-recommends \
curl ca-certificates build-essential pkg-config \
&& rm -rf /var/lib/apt/lists/*

# The emulator needs NIGHTLY Rust (for -Zbuild-std); install it via rustup
RUN rustup toolchain install nightly && rustup default nightly
RUN rustup target add wasm32-unknown-unknown
RUN cargo install wasm-pack

# Node.js for the webpack build
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
&& apt-get install -y nodejs && rm -rf /var/lib/apt/lists/*

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
