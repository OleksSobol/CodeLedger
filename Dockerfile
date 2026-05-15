# Stage 1 — build Flutter web
FROM ghcr.io/cirruslabs/flutter:stable AS builder
WORKDIR /app
COPY pubspec.yaml ./
RUN flutter pub get
COPY . .
RUN flutter build web --release

# Stage 2 — serve with nginx
FROM nginx:alpine
COPY --from=builder /app/build/web /usr/share/nginx/html
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
