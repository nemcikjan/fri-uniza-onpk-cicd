FROM node:current-alpine

# Links the image (GitHub package) to your fork on ghcr.io
LABEL org.opencontainers.image.source="https://github.com/nemcikjan/fri-uniza-onpk-cicd"

WORKDIR /app

COPY src/package.json .
RUN npm install --verbose

COPY src .

CMD [ "npm", "start" ]
