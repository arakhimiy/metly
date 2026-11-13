# syntax=docker/dockerfile:1.7
# Nameshake API image. Build context: backend/  →  docker build -t metly-api backend

FROM node:24-bookworm-slim AS deps
WORKDIR /app
ENV NPM_CONFIG_UPDATE_NOTIFIER=false NPM_CONFIG_FUND=false
COPY package.json package-lock.json ./
RUN npm ci

FROM deps AS build
COPY . .
RUN npx prisma generate && npx nest build

FROM node:24-bookworm-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production NPM_CONFIG_UPDATE_NOTIFIER=false NPM_CONFIG_FUND=false
COPY package.json package-lock.json ./
# Production dependencies only; the Prisma CLI is a runtime dependency because the container
# applies pending migrations on start (Prisma takes an advisory lock, so parallel starts are safe).
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=build /app/dist ./dist
COPY prisma ./prisma
COPY prisma.config.ts ./
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||3000)+'/health/live').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["sh", "-c", "npx prisma migrate deploy && exec node dist/main.js"]
