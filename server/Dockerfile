FROM node:22-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY relay.js ./
ENV PORT=8080
EXPOSE 8080
CMD ["node", "relay.js"]
