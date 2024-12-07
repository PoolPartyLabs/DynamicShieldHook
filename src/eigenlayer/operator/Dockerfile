# Usando uma imagem base oficial do Node.js
FROM node:18-alpine AS base

RUN apk add --no-cache \
    libc6-compat \
    libpng \
    libjpeg-turbo \
    libwebp \
    vips-dev \
    gcc \
    g++ \
    make \
    python3 \
    libpq-dev
    
# Criando o diretório de trabalho dentro do container
WORKDIR /app

# Copiando o package.json e instalando as dependências
COPY package.json ./
RUN yarn

# Instalando o PM2 globalmente
RUN yarn add pm2 -g

# Copiando o restante dos arquivos para o container
COPY . .

ENV NODE_ENV production

# Expondo a porta da API
EXPOSE 5051

# Usando PM2 para rodar o servidor com auto-restart
CMD ["pm2-runtime", "server.js"]
