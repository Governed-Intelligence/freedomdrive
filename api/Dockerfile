# syntax=docker/dockerfile:1.7
# =============================================================================
# Freedom Supercars API — production container
# Multi-stage build producing a distroless Node 20 image
# =============================================================================

# ---- Stage 1: deps ----------------------------------------------------------
FROM node:20.18-bookworm-slim AS deps
WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci --omit=dev --no-audit --no-fund

# ---- Stage 2: build / verify -----------------------------------------------
FROM node:20.18-bookworm-slim AS build
WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci --no-audit --no-fund

COPY src ./src
COPY scripts ./scripts
COPY db ./db

# (Optional) lint/test step — commented out; enable when you have tests:
# RUN npm test

# ---- Stage 3: runtime (distroless, non-root) -------------------------------
FROM gcr.io/distroless/nodejs20-debian12:nonroot AS runtime
WORKDIR /app

# Pull node_modules from deps stage (production only)
COPY --from=deps  /app/node_modules ./node_modules
# App code
COPY --from=build /app/src      ./src
COPY --from=build /app/scripts  ./scripts
COPY --from=build /app/db       ./db
COPY package.json ./

ENV NODE_ENV=production
ENV PORT=8080

EXPOSE 8080
USER nonroot

# Distroless nodejs image has /nodejs/bin/node as default entrypoint
CMD ["src/index.js"]
