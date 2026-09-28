# syntax=docker/dockerfile:1.7
# Freedom Supercars Web - static React app served by nginx on Cloud Run

FROM node:20.18-bookworm-slim AS build
WORKDIR /app

ARG VITE_API_URL=""
ENV VITE_API_URL=$VITE_API_URL

COPY package.json package-lock.json* ./
RUN npm ci --no-audit --no-fund || npm install --no-audit --no-fund
COPY . .
RUN npm run build

FROM nginx:1.27-alpine AS runtime
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
RUN rm -f /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
ENV PORT=8080
ENV API_URL=""
EXPOSE 8080
# nginx image auto-runs envsubst on /etc/nginx/templates/*.template before starting
