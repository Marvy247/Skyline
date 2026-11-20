/** @type {import('next').NextConfig} */
const nextConfig = {
  typescript: {
    ignoreBuildErrors: true,
  },
  eslint: {
    ignoreDuringBuilds: true,
  },
  webpack: (config) => {
    // These are OPTIONAL peer dependencies of the wagmi connector barrel
    // (MetaMask SDK and WalletConnect's pino logger). Skyline only uses the
    // `injected` connector, so these are never reached at runtime. Aliasing
    // them to false keeps the production build warning-free and drops the
    // unused connectors from the bundle.
    config.resolve.alias = {
      ...config.resolve.alias,
      '@react-native-async-storage/async-storage': false,
      'pino-pretty': false,
    }
    return config
  },
}

module.exports = nextConfig
