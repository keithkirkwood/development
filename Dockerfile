FROM nginx:alpine

WORKDIR /usr/share/nginx/html/
# Update copy paths to reflect configured build outputs
COPY ["public/", "."]
