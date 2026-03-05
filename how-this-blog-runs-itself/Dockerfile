FROM hugomods/hugo:reg-0.154.5 AS builder
WORKDIR /src
COPY . .
RUN hugo --gc --minify

FROM nginx:alpine
COPY --from=builder /src/public /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
