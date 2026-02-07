FROM node:20-alpine

RUN apk add --no-cache python3 make g++

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci --production
RUN apk del python3 make g++

COPY relay-server.js ./

RUN mkdir -p /data

EXPOSE 9080

CMD ["node", "relay-server.js"]
