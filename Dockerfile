# Use official Node.js LTS
FROM node:18-alpine

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy source code (excludes spec/ via .dockerignore)
COPY src ./src
COPY compose.yaml ./

# Expose port
EXPOSE 3000

# Start the app
CMD ["node", "src/index.js"]