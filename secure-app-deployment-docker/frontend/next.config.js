/** @type {import('next').NextConfig} */
const nextConfig = {
  // Required for the multi-stage Dockerfile.
  // Produces .next/standalone/ — a self-contained server with only
  // the required node_modules copied in. No source files.
  output: 'standalone',
}

module.exports = nextConfig
